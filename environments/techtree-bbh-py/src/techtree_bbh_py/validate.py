from __future__ import annotations

import json
from hashlib import sha256
from pathlib import Path
from typing import Any

from .integrations import SEARCH_SUMMARY_PATH, build_evidence_refs, build_review_provenance_note
from .models import ValidationResult
from .score import score_workspace


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _json_text(value: object) -> str:
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def _sha256_path(path: Path) -> str | None:
    if not path.exists():
        return None
    return f"sha256:{sha256(path.read_bytes()).hexdigest()}"


def _artifact_sha256(artifact_manifest: object, relative_path: object) -> str | None:
    if not isinstance(relative_path, str) or not isinstance(artifact_manifest, list):
        return None

    for entry in artifact_manifest:
        if not isinstance(entry, dict):
            continue
        if entry.get("path") == relative_path and isinstance(entry.get("sha256"), str):
            return str(entry["sha256"])

    return None


def validate_workspace(
    workspace_dir: Path,
    *,
    run_id: str | None = None,
    validator_role: str = "official",
    tolerance: float = 0.01,
) -> ValidationResult:
    workspace = Path(workspace_dir)
    run_source_path = workspace / "run.source.yaml"
    review_source_path = workspace / "review.source.yaml"
    validation_path = workspace / "dist" / "validation.json"
    search_config_path = workspace / "search.config.yaml"
    search_summary_path = workspace / SEARCH_SUMMARY_PATH

    run_source = _read_json(run_source_path)
    search_config = _read_json(search_config_path)
    search_summary = _read_json(search_summary_path)
    reproduced = score_workspace(workspace)
    stored_score = run_source.get("score") if isinstance(run_source.get("score"), dict) else {}
    paths = run_source.get("paths") if isinstance(run_source.get("paths"), dict) else {}
    artifact_manifest = run_source.get("artifact_manifest")

    stored_raw = float(stored_score.get("raw") or 0.0)
    stored_normalized = float(stored_score.get("normalized") or 0.0)
    matches = abs(reproduced.raw_score - stored_raw) <= tolerance and (
        abs(reproduced.normalized_score - stored_normalized) <= tolerance
    )
    submitted_program_sha256 = _artifact_sha256(artifact_manifest, paths.get("best_program_path"))
    reproduced_program_sha256 = (
        _sha256_path(workspace / paths["best_program_path"])
        if isinstance(paths.get("best_program_path"), str)
        else None
    )
    artifact_match = submitted_program_sha256 is not None and submitted_program_sha256 == reproduced_program_sha256
    result = "confirmed" if matches else "rejected"
    provenance_note = build_review_provenance_note(
        search_config,
        search_summary,
        result=result,
        reproduced_raw_score=reproduced.raw_score,
        reproduced_normalized_score=reproduced.normalized_score,
        tolerance=tolerance,
    )

    review_source = {
        "schema_version": "techtree.bbh.review-source.v1",
        "target": {"type": "run", "id": run_id or workspace.name},
        "kind": "validation",
        "method": "replay",
        "result": result,
        "summary": (
            "Replay confirmed the submitted BBH score within tolerance."
            if matches
            else "Replay diverged from the submitted BBH score."
        ),
        "evidence": build_evidence_refs(),
        "paths": {
            "replication_workspace": ".",
            "verdict_path": "outputs/verdict.json",
            "report_path": "outputs/report.html",
            "log_path": "outputs/run.log",
        },
        "bbh": {
            "role": validator_role,
            "reproduced_raw_score": reproduced.raw_score,
            "reproduced_normalized_score": reproduced.normalized_score,
            "raw_abs_tolerance": tolerance,
            "evaluator_kind": str(search_summary.get("evaluator", {}).get("kind") or "hypotest"),
            "dataset_ref": str(search_summary.get("evaluator", {}).get("dataset_ref") or ""),
            "scorer_version": str(search_summary.get("evaluator", {}).get("scorer_version") or "hypotest-v0.1"),
            "assignment_ref": run_source.get("bbh", {}).get("assignment_ref"),
            "submitted_program_sha256": submitted_program_sha256,
            "reproduced_program_sha256": reproduced_program_sha256,
            "score_match": matches,
            "artifact_match": artifact_match,
        },
        "notes": provenance_note,
    }

    review_source_path.write_text(_json_text(review_source), encoding="utf-8")
    validation_path.write_text(
        _json_text(
            {
                "result": result,
                "matches": matches,
                "reproduced_raw_score": reproduced.raw_score,
                "reproduced_normalized_score": reproduced.normalized_score,
                "raw_abs_tolerance": tolerance,
                "submitted_program_sha256": submitted_program_sha256,
                "reproduced_program_sha256": reproduced_program_sha256,
                "score_match": matches,
                "artifact_match": artifact_match,
            }
        ),
        encoding="utf-8",
    )

    return ValidationResult(
        result=result,
        reproduced_raw_score=reproduced.raw_score,
        reproduced_normalized_score=reproduced.normalized_score,
        raw_abs_tolerance=tolerance,
        matches=matches,
        submitted_program_sha256=submitted_program_sha256,
        reproduced_program_sha256=reproduced_program_sha256,
        artifact_match=artifact_match,
        review_source_path=review_source_path,
    )
