from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .models import ValidationResult
from .score import score_workspace


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _json_text(value: object) -> str:
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


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

    reproduced = score_workspace(workspace)
    run_source = _read_json(run_source_path)
    stored_score = run_source.get("score") if isinstance(run_source.get("score"), dict) else {}

    stored_raw = float(stored_score.get("raw") or 0.0)
    stored_normalized = float(stored_score.get("normalized") or 0.0)
    matches = abs(reproduced.raw_score - stored_raw) <= tolerance and (
        abs(reproduced.normalized_score - stored_normalized) <= tolerance
    )
    result = "confirmed" if matches else "rejected"

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
            "scorer_version": "bbh-v0.1",
            "assignment_ref": run_source.get("bbh", {}).get("assignment_ref"),
        },
        "notes": None,
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
        review_source_path=review_source_path,
    )
