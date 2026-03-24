from __future__ import annotations

import hashlib
import json
import mimetypes
import platform
import socket
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml
from Crypto.Hash import keccak
from pydantic import ValidationError

from .canonical import bytes32_hex_from_digest, canonicalize, domain_hash, sha256_hex, sha256_prefixed
from .filesystem import DiscoveredFile, WorkspaceError, expand_globs, normalize_relative_path, relative_posix_path
from .models import (
    ArtifactEnvCanonical,
    ArtifactEvalSource,
    ArtifactManifestV1,
    ArtifactNotebookSection,
    ArtifactSourceV1,
    CompilationResult,
    EvalGenerator,
    EvalInstance,
    NodeHeaderV1,
    NotebookFileEntry,
    PayloadFileEntry,
    PayloadIndexV1,
    ProvenanceCanonical,
    ReviewAttachment,
    ReviewEvidenceCanonical,
    ReviewManifestV1,
    ReviewProvenance,
    ReviewSourceV1,
    RunEnvObserved,
    RunManifestV1,
    RunMetrics,
    RunOutputFile,
    RunOutputs,
    RunProvenance,
    RunSourceV1,
    VerificationResult,
    ZERO_ADDRESS,
    ZERO_BYTES32,
)

SCHEMA_VERSIONS = {
    "artifact": "techtree.artifact-manifest.v1",
    "artifact_source": "techtree.artifact-source.v1",
    "payload_index": "techtree.payload-index.v1",
    "review": "techtree.review-manifest.v1",
    "review_source": "techtree.review-source.v1",
    "run": "techtree.run-manifest.v1",
    "run_source": "techtree.run-source.v1",
}


def _workspace_root_from_source(source_path: Path) -> Path:
    return source_path.parent.resolve()


def _load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"Source manifest must be a mapping: {path}")
    return data


def _detect_source_type(data: dict[str, Any]) -> str:
    schema_version = data.get("schema_version")
    mapping = {
        SCHEMA_VERSIONS["artifact_source"]: "artifact",
        SCHEMA_VERSIONS["run_source"]: "run",
        SCHEMA_VERSIONS["review_source"]: "review",
    }
    if schema_version not in mapping:
        raise ValueError(f"Unsupported schema_version: {schema_version!r}")
    return mapping[schema_version]


def _discover_source_file(workspace_path: Path) -> Path:
    if workspace_path.is_file():
        return workspace_path
    candidates = []
    for name in ("artifact.source.yaml", "run.source.yaml", "review.source.yaml"):
        candidate = workspace_path / name
        if candidate.exists():
            candidates.append(candidate)
    if not candidates:
        raise FileNotFoundError(f"No source manifest found in {workspace_path}")
    if len(candidates) > 1:
        raise ValueError(f"Multiple source manifests found in {workspace_path}: {candidates}")
    return candidates[0]


def _media_type_for_path(path: str) -> str:
    suffix = Path(path).suffix.lower()
    if suffix == ".py":
        return "text/x-python"
    if suffix in {".md", ".markdown"}:
        return "text/markdown"
    if suffix == ".json":
        return "application/json"
    if suffix in {".yaml", ".yml"}:
        return "application/yaml"
    if suffix == ".toml":
        return "text/plain"
    if suffix == ".html":
        return "text/html"
    if suffix in {".txt", ".log"}:
        return "text/plain"
    guessed, _ = mimetypes.guess_type(path)
    return guessed or "application/octet-stream"


def _sha256_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            size += len(chunk)
            digest.update(chunk)
    return digest.hexdigest(), size


def _collect_payload_files(
    workspace_root: Path,
    includes: list[str],
    excludes: list[str],
) -> list[DiscoveredFile]:
    files = expand_globs(workspace_root, includes=includes, excludes=excludes)
    for discovered in files:
        if discovered.path.is_symlink():
            resolved = discovered.path.resolve()
            if workspace_root.resolve() not in resolved.parents and resolved != workspace_root.resolve():
                raise WorkspaceError(f"Symlink escapes workspace: {discovered.relpath}")
    return files


def _payload_entry(relpath: str, path: Path, role: str) -> PayloadFileEntry:
    sha256, size = _sha256_file(path)
    return PayloadFileEntry(
        path=relpath,
        sha256=sha256,
        size=size,
        media_type=_media_type_for_path(relpath),
        role=role,
    )


def _role_for_artifact(path: str, source: ArtifactSourceV1) -> str:
    if path == source.notebook.entrypoint or path.startswith("notebooks/"):
        return "notebook"
    if path.startswith("eval/"):
        return "eval"
    if path == source.env.lockfile_path:
        return "lockfile"
    if path.startswith("attestations/"):
        return "attestation"
    return "supporting"


def _role_for_run(path: str) -> str:
    if path.endswith("verdict.json"):
        return "verdict"
    if path.endswith("run.log") or path.endswith(".log"):
        return "log"
    if path.endswith(".html"):
        return "report"
    return "output"


def _role_for_review(path: str) -> str:
    return "attachment"


def _canonical_payload_index(node_type: str, files: list[PayloadFileEntry]) -> PayloadIndexV1:
    return PayloadIndexV1(schema_version=SCHEMA_VERSIONS["payload_index"], node_type=node_type, files=files)


def _compile_artifact(source: ArtifactSourceV1, source_path: Path, workspace_root: Path, author: str) -> CompilationResult:
    payload_files = _collect_payload_files(
        workspace_root,
        includes=source.notebook.include,
        excludes=source.notebook.exclude,
    )
    if not any(file.relpath == source.notebook.entrypoint for file in payload_files):
        raise WorkspaceError(f"Notebook entrypoint missing from payload set: {source.notebook.entrypoint}")
    if not any(file.relpath == source.env.lockfile_path for file in payload_files):
        raise WorkspaceError(f"Lockfile missing from payload set: {source.env.lockfile_path}")
    if source.provenance:
        for attestation in source.provenance.build_attestation_files:
            if not any(file.relpath == attestation for file in payload_files):
                raise WorkspaceError(f"Attestation missing from payload set: {attestation}")

    payload_entries = [
        _payload_entry(discovered.relpath, discovered.path, _role_for_artifact(discovered.relpath, source))
        for discovered in payload_files
    ]
    payload_index = _canonical_payload_index("artifact", payload_entries)
    payload_hash = sha256_prefixed("TECHTREE-PAYLOAD-V1", payload_index.model_dump(exclude_none=True, mode="json"))

    notebook_files = [
        NotebookFileEntry(
            path=entry.path,
            sha256=entry.sha256,
            size=entry.size,
            media_type=entry.media_type,
            role=entry.role,
        )
        for entry in payload_entries
    ]
    manifest = ArtifactManifestV1(
        schema_version=SCHEMA_VERSIONS["artifact"],
        kind="capsule" if source.eval else "notebook",
        title=source.title,
        summary=source.summary,
        parents=source.parents,
        notebook=ArtifactNotebookSection(
            entrypoint=source.notebook.entrypoint,
            marimo_version=source.notebook.marimo_version,
            files=notebook_files,
        ),
        env=ArtifactEnvCanonical(
            lockfile_path=source.env.lockfile_path,
            image=source.env.image,
            system=source.env.system,
            runtime_policy=source.env.runtime_policy,
            external_resources=source.env.external_resources,
        ),
        provenance=ProvenanceCanonical(
            source_repo=source.provenance.source_repo,
            source_commit=source.provenance.source_commit,
            build_attestation_files=source.provenance.build_attestation_files,
        )
        if source.provenance
        else None,
        claims=source.claims,
        notes=source.notes,
        sources=source.sources,
        licenses=source.licenses,
        eval=source.eval,
        payload_hash=payload_hash,
    )
    manifest_dict = manifest.model_dump(exclude_none=True, mode="json")
    manifest_hash = bytes32_hex_from_digest(domain_hash("TECHTREE-ARTIFACT-V1", manifest_dict))
    header = _artifact_header(manifest, manifest_hash, payload_hash, author)
    return _finalize_result(
        node_type="artifact",
        source_path=source_path,
        workspace_root=workspace_root,
        payload_index=payload_index,
        manifest=manifest,
        header=header,
        payload_hash=payload_hash,
        manifest_hash=manifest_hash,
    )


def _artifact_header(manifest: ArtifactManifestV1, node_id: str, payload_hash: str, author: str) -> NodeHeaderV1:
    subject_id = ZERO_BYTES32
    for parent in manifest.parents:
        if parent.relation == "revision":
            subject_id = parent.artifact_id
            break
    else:
        if manifest.parents:
            subject_id = manifest.parents[0].artifact_id
    aux_id = ZERO_BYTES32
    flags = 0
    if manifest.eval is not None:
        flags |= 1 << 0
        if manifest.eval.mode == "family":
            flags |= 1 << 1
    return NodeHeaderV1(
        id=node_id,
        subject_id=subject_id,
        aux_id=aux_id,
        payload_hash=payload_hash,
        node_type=1,
        schema_version=1,
        flags=flags,
        author=author,
    )


def _load_run_outputs(workspace_root: Path, execution: str) -> tuple[list[PayloadFileEntry], RunOutputs | None, RunEnvObserved | None, RunMetrics | None, RunProvenance | None, str]:
    output_root = workspace_root / execution
    if not output_root.exists():
        raise FileNotFoundError(f"Run output directory does not exist: {output_root}")
    discovered = []
    for path in sorted(output_root.rglob("*")):
        if path.is_file():
            relpath = relative_posix_path(path, workspace_root)
            sha256, size = _sha256_file(path)
            discovered.append(
                PayloadFileEntry(
                    path=relpath,
                    sha256=sha256,
                    size=size,
                    media_type=_media_type_for_path(relpath),
                    role=_role_for_run(relpath),
                )
            )
    outputs = RunOutputs(files=[RunOutputFile(**entry.model_dump()) for entry in discovered])
    primary = None
    verdict = None
    log_ref = None
    if discovered:
        primary = next((entry.path for entry in discovered if entry.path.endswith("verdict.json")), discovered[0].path)
        verdict = next((entry.path for entry in discovered if entry.path.endswith("verdict.json")), None)
        log_ref = next((entry.path for entry in discovered if entry.path.endswith("run.log") or entry.path.endswith(".log")), None)
        outputs = RunOutputs(files=[RunOutputFile(**entry.model_dump()) for entry in discovered], primary_output=primary, verdict_ref=verdict, log_ref=log_ref)

    verdict_metrics = None
    score = None
    if verdict:
        verdict_path = workspace_root / verdict
        try:
            with verdict_path.open("r", encoding="utf-8") as handle:
                verdict_data = json.load(handle)
            metrics_data = verdict_data.get("metrics") if isinstance(verdict_data, dict) else None
            if isinstance(metrics_data, dict):
                score = metrics_data.get("score")
                if score is None and "total_score" in metrics_data:
                    score = metrics_data.get("total_score")
                values = metrics_data.get("values") if isinstance(metrics_data.get("values"), dict) else {}
                verdict_metrics = RunMetrics(score=score if isinstance(score, (int, float)) else None, values=values)
            elif isinstance(verdict_data, dict) and isinstance(verdict_data.get("score"), (int, float)):
                score = verdict_data.get("score")
                verdict_metrics = RunMetrics(score=score, values={})
        except FileNotFoundError:
            pass

    env_observed = RunEnvObserved(
        image=None,
        python=platform.python_version(),
        platform=f"{platform.system().lower()}/{platform.machine().lower()}",
    )
    provenance = RunProvenance(
        runner_id=socket.gethostname(),
        attestation_files=[],
    )
    return discovered, outputs, env_observed, verdict_metrics, provenance, "completed" if discovered else "running"


def _compile_run(source: RunSourceV1, source_path: Path, workspace_root: Path, author: str) -> CompilationResult:
    output_dir = source.execution.output_dir
    payload_entries, outputs, env_observed, metrics, run_provenance, status = _load_run_outputs(workspace_root, output_dir)
    payload_index = _canonical_payload_index("run", payload_entries)
    payload_hash = sha256_prefixed("TECHTREE-PAYLOAD-V1", payload_index.model_dump(exclude_none=True, mode="json"))
    manifest = RunManifestV1(
        schema_version=SCHEMA_VERSIONS["run"],
        artifact_id=source.artifact_id,
        executor=source.executor,
        origin=source.origin,
        instance=source.instance,
        status=status,
        env_observed=env_observed,
        outputs=outputs,
        metrics=metrics,
        run_provenance=run_provenance,
        payload_hash=payload_hash,
    )
    manifest_hash = bytes32_hex_from_digest(domain_hash("TECHTREE-RUN-V1", manifest.model_dump(exclude_none=True, mode="json")))
    header = _run_header(manifest, manifest_hash, payload_hash, author)
    return _finalize_result(
        node_type="run",
        source_path=source_path,
        workspace_root=workspace_root,
        payload_index=payload_index,
        manifest=manifest,
        header=header,
        payload_hash=payload_hash,
        manifest_hash=manifest_hash,
    )


def _keccak_bytes32(*parts: str) -> str:
    hasher = keccak.new(digest_bits=256)
    for part in parts:
        hasher.update(part.encode("utf-8"))
    return "0x" + hasher.digest().hex()


def _run_header(manifest: RunManifestV1, node_id: str, payload_hash: str, author: str) -> NodeHeaderV1:
    flags = 0
    if manifest.metrics and manifest.metrics.score is not None:
        flags |= 1 << 0
    if manifest.status == "failed":
        flags |= 1 << 1
    aux_id = _keccak_bytes32(manifest.executor.type, manifest.executor.id)
    return NodeHeaderV1(
        id=node_id,
        subject_id=manifest.artifact_id,
        aux_id=aux_id,
        payload_hash=payload_hash,
        node_type=2,
        schema_version=1,
        flags=flags,
        author=author,
    )


def _compile_review(source: ReviewSourceV1, source_path: Path, workspace_root: Path, author: str) -> CompilationResult:
    attachments = _collect_payload_files(workspace_root, source.evidence.attachments.include, source.evidence.attachments.exclude)
    payload_entries = [
        PayloadFileEntry(
            path=attachment.relpath,
            sha256=_sha256_file(attachment.path)[0],
            size=_sha256_file(attachment.path)[1],
            media_type=_media_type_for_path(attachment.relpath),
            role=_role_for_review(attachment.relpath),
        )
        for attachment in attachments
    ]
    payload_index = _canonical_payload_index("review", payload_entries)
    payload_hash = sha256_prefixed("TECHTREE-PAYLOAD-V1", payload_index.model_dump(exclude_none=True, mode="json"))
    evidence = ReviewEvidenceCanonical(
        refs=source.evidence.refs,
        attachments=[
            ReviewAttachment(
                path=entry.path,
                sha256=entry.sha256,
                size=entry.size,
                media_type=entry.media_type,
                role=entry.role,
            )
            for entry in payload_entries
        ],
    )
    manifest = ReviewManifestV1(
        schema_version=SCHEMA_VERSIONS["review"],
        target=source.target,
        kind=source.kind,
        method=source.method,
        scope=source.scope,
        result=source.result,
        summary=source.summary,
        findings=source.findings,
        evidence=evidence,
        review_provenance=ReviewProvenance(reviewer_id=author, attestation_files=[]),
        payload_hash=payload_hash,
    )
    manifest_hash = bytes32_hex_from_digest(domain_hash("TECHTREE-REVIEW-V1", manifest.model_dump(exclude_none=True, mode="json")))
    header = _review_header(manifest, manifest_hash, payload_hash, author)
    return _finalize_result(
        node_type="review",
        source_path=source_path,
        workspace_root=workspace_root,
        payload_index=payload_index,
        manifest=manifest,
        header=header,
        payload_hash=payload_hash,
        manifest_hash=manifest_hash,
    )


def _review_header(manifest: ReviewManifestV1, node_id: str, payload_hash: str, author: str) -> NodeHeaderV1:
    flags = 1 if manifest.kind == "validation" else 0
    scope_path = manifest.scope.path or ""
    aux_id = _keccak_bytes32(manifest.scope.level, ":" + scope_path)
    return NodeHeaderV1(
        id=node_id,
        subject_id=manifest.target.id,
        aux_id=aux_id,
        payload_hash=payload_hash,
        node_type=3,
        schema_version=1,
        flags=flags,
        author=author,
    )


def _finalize_result(
    *,
    node_type: str,
    source_path: Path,
    workspace_root: Path,
    payload_index: PayloadIndexV1,
    manifest: ArtifactManifestV1 | RunManifestV1 | ReviewManifestV1,
    header: NodeHeaderV1,
    payload_hash: str,
    manifest_hash: str,
) -> CompilationResult:
    checksum_lines = [
        f"{sha256_hex(canonicalize(payload_index.model_dump(exclude_none=True, mode='json')))}  payload.index.json",
        f"{sha256_hex(canonicalize(manifest.model_dump(exclude_none=True, mode='json')))}  {node_type}.manifest.json",
        f"{sha256_hex(canonicalize(header.model_dump(exclude_none=True, mode='json')))}  node-header.json",
    ]
    dist_dir = str((source_path.parent / "dist").resolve())
    return CompilationResult(
        node_type=node_type,
        source_path=str(source_path),
        workspace_root=str(workspace_root),
        payload_index=payload_index,
        manifest=manifest,
        header=header,
        node_id=manifest_hash,
        payload_hash=payload_hash,
        manifest_hash=manifest_hash,
        dist_dir=dist_dir,
        checksum_lines=checksum_lines,
    )


def load_source_manifest(source_path: Path) -> tuple[str, ArtifactSourceV1 | RunSourceV1 | ReviewSourceV1]:
    raw = _load_yaml(source_path)
    kind = _detect_source_type(raw)
    if kind == "artifact":
        return kind, ArtifactSourceV1.model_validate(raw)
    if kind == "run":
        return kind, RunSourceV1.model_validate(raw)
    return kind, ReviewSourceV1.model_validate(raw)


def compile_workspace(workspace_path: str | Path, author: str = ZERO_ADDRESS) -> CompilationResult:
    source_path = _discover_source_file(Path(workspace_path))
    kind, source = load_source_manifest(source_path)
    workspace_root = _workspace_root_from_source(source_path)
    if kind == "artifact":
        return _compile_artifact(source, source_path, workspace_root, author)
    if kind == "run":
        return _compile_run(source, source_path, workspace_root, author)
    return _compile_review(source, source_path, workspace_root, author)


def write_compilation(result: CompilationResult, output_dir: str | Path | None = None) -> dict[str, Path]:
    dist = Path(output_dir) if output_dir is not None else Path(result.dist_dir)
    dist.mkdir(parents=True, exist_ok=True)
    files = {
        "payload.index.json": dist / "payload.index.json",
        f"{result.node_type}.manifest.json": dist / f"{result.node_type}.manifest.json",
        "node-header.json": dist / "node-header.json",
        "checksums.txt": dist / "checksums.txt",
    }
    files["payload.index.json"].write_bytes(canonicalize(result.payload_index.model_dump(exclude_none=True, mode="json")))
    files[f"{result.node_type}.manifest.json"].write_bytes(canonicalize(result.manifest.model_dump(exclude_none=True, mode="json")))
    files["node-header.json"].write_bytes(canonicalize(result.header.model_dump(exclude_none=True, mode="json")))
    files["checksums.txt"].write_text("\n".join(result.checksum_lines) + "\n", encoding="utf-8")
    return files


def _read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def verify_workspace(workspace_path: str | Path, author: str = ZERO_ADDRESS) -> VerificationResult:
    source_path = _discover_source_file(Path(workspace_path))
    result = compile_workspace(source_path, author=author)
    dist = Path(result.dist_dir)
    manifest_path = dist / f"{result.node_type}.manifest.json"
    payload_path = dist / "payload.index.json"
    header_path = dist / "node-header.json"
    messages = []
    manifest_match = payload_match = header_match = False
    try:
        manifest_match = _read_json(manifest_path) == result.manifest.model_dump(exclude_none=True, mode="json")
        payload_match = _read_json(payload_path) == result.payload_index.model_dump(exclude_none=True, mode="json")
        header_match = _read_json(header_path) == result.header.model_dump(exclude_none=True, mode="json")
    except FileNotFoundError as exc:
        messages.append(str(exc))
    ok = manifest_match and payload_match and header_match
    if not ok and not messages:
        messages.append("Compilation outputs did not match recomputed values")
    return VerificationResult(
        ok=ok,
        node_type=result.node_type,
        node_id=result.node_id,
        expected_node_id=result.manifest_hash,
        payload_hash_match=result.payload_hash == result.manifest.payload_hash,
        header_match=header_match,
        manifest_match=manifest_match and payload_match,
        messages=messages,
    )


def export_schema_files(output_dir: str | Path) -> dict[str, Path]:
    from .schema_export import export_all_schemas

    return export_all_schemas(Path(output_dir))
