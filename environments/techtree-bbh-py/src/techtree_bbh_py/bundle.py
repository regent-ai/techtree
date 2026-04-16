from __future__ import annotations

import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from .models import BundleFile, RunBundle


def utc_now_iso() -> str:
    return datetime.now(tz=timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_bytes(content: bytes) -> str:
    digest = hashlib.sha256()
    digest.update(content)
    return digest.hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _copy_tree(source: Path, destination: Path) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)


def _collect_files(workspace_dir: Path) -> tuple[BundleFile, ...]:
    names = [
        "analysis.py",
        "search.config.yaml",
        "eval/hypotest_skydiscover.py",
        "solver/initial_program.py",
        "task.json",
        "protocol.md",
        "rubric.json",
        "final_answer.md",
        "run.source.yaml",
        "review.source.yaml",
        "outputs/verdict.json",
        "outputs/skydiscover/search.log",
        "outputs/skydiscover/search_summary.json",
        "outputs/skydiscover/best_program.py",
        "outputs/skydiscover/evaluator_artifacts.json",
        "outputs/skydiscover/latest_checkpoint.txt",
        "outputs/skydiscover/best_solution.patch",
    ]
    files: list[BundleFile] = []
    for name in names:
        path = workspace_dir / name
        if path.exists():
            files.append(BundleFile(name=name, path=path, sha256=sha256_file(path), size_bytes=path.stat().st_size))
    data_dir = workspace_dir / "data"
    if data_dir.exists():
        for path in sorted(data_dir.iterdir()):
            if path.is_file():
                relative_name = f"data/{path.name}"
                files.append(BundleFile(name=relative_name, path=path, sha256=sha256_file(path), size_bytes=path.stat().st_size))
    return tuple(files)


def write_run_bundle(
    workspace_dir: Path,
    bundle_dir: Path,
    *,
    run_id: str,
    split: str,
    source_dataset: str,
    capsule_id: str,
) -> RunBundle:
    bundle_dir.mkdir(parents=True, exist_ok=True)
    snapshot_dir = bundle_dir / "workspace"
    _copy_tree(workspace_dir, snapshot_dir)

    files = _collect_files(snapshot_dir)
    run_bundle = RunBundle(
        run_id=run_id,
        capsule_id=capsule_id,
        split=split,
        source_dataset=source_dataset,
        workspace_dir=workspace_dir,
        bundle_dir=bundle_dir,
        created_at=utc_now_iso(),
        files=files,
    )

    payload = {
        "run_id": run_bundle.run_id,
        "capsule_id": run_bundle.capsule_id,
        "split": run_bundle.split,
        "source_dataset": run_bundle.source_dataset,
        "workspace_dir": str(run_bundle.workspace_dir),
        "bundle_dir": str(run_bundle.bundle_dir),
        "created_at": run_bundle.created_at,
        "files": [
            {
                "name": file.name,
                "path": str(file.path.relative_to(snapshot_dir)),
                "sha256": file.sha256,
                "size_bytes": file.size_bytes,
            }
            for file in run_bundle.files
        ],
    }
    (bundle_dir / "run.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return run_bundle
