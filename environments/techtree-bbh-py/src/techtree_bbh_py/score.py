from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .models import ScoreResult


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _json_text(value: object) -> str:
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def _clamp_normalized(value: float) -> float:
    return max(0.0, min(1.0, value))


def _coerce_breakdown(verdict: dict[str, Any], rubric_items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    breakdown = verdict.get("rubric_breakdown")
    if isinstance(breakdown, list):
        normalized: list[dict[str, Any]] = []
        for item in breakdown:
            if not isinstance(item, dict):
                continue
            normalized.append(
                {
                    "rubric_item_id": str(item.get("rubric_item_id") or "unknown"),
                    "points_awarded": float(item.get("points_awarded") or 0.0),
                    "points_possible": float(item.get("points_possible") or 0.0),
                    "notes": item.get("notes"),
                }
            )
        if normalized:
            return normalized

    decision = str(verdict.get("decision") or "inconclusive")
    synthesized: list[dict[str, Any]] = []
    for rubric_item in rubric_items:
        rubric_item_id = str(rubric_item.get("rubric_item_id") or "unknown")
        points_possible = float(rubric_item.get("points_possible") or 0.0)
        points_awarded = 0.0
        if rubric_item_id == "final_objective" and decision in {"support", "reject"}:
            points_awarded = points_possible
        synthesized.append(
            {
                "rubric_item_id": rubric_item_id,
                "points_awarded": points_awarded,
                "points_possible": points_possible,
                "notes": "Synthesized from verdict decision.",
            }
        )
    return synthesized


def _score_from_verdict(
    verdict: dict[str, Any],
    rubric_json: dict[str, Any],
) -> tuple[float, float, list[dict[str, Any]]]:
    rubric_items = rubric_json.get("items")
    if not isinstance(rubric_items, list):
        rubric_items = []

    breakdown = _coerce_breakdown(verdict, rubric_items)
    max_points = sum(float(item.get("points_possible") or 0.0) for item in breakdown)

    metrics = verdict.get("metrics")
    if isinstance(metrics, dict) and isinstance(metrics.get("raw_score"), (int, float)):
        raw_score = float(metrics["raw_score"])
    else:
        raw_score = sum(float(item.get("points_awarded") or 0.0) for item in breakdown)

    if isinstance(metrics, dict) and isinstance(metrics.get("normalized_score"), (int, float)):
        normalized_score = _clamp_normalized(float(metrics["normalized_score"]))
    elif max_points > 0:
        normalized_score = _clamp_normalized(raw_score / max_points)
    else:
        normalized_score = 0.0

    return raw_score, normalized_score, breakdown


def score_workspace(workspace_dir: Path) -> ScoreResult:
    workspace = Path(workspace_dir)
    verdict_path = workspace / "outputs" / "verdict.json"
    rubric_path = workspace / "rubric.json"
    run_source_path = workspace / "run.source.yaml"
    report_path = workspace / "outputs" / "report.html"
    score_path = workspace / "dist" / "score.json"

    verdict = _read_json(verdict_path)
    rubric_json = _read_json(rubric_path)
    run_source = _read_json(run_source_path)

    raw_score, normalized_score, breakdown = _score_from_verdict(verdict, rubric_json)
    decision = str(verdict.get("decision") or "inconclusive")
    justification = str(verdict.get("justification") or "")
    status = "failed" if str(verdict.get("status") or "ok") == "error" else "completed"

    verdict["metrics"] = {
        "raw_score": raw_score,
        "normalized_score": normalized_score,
    }
    verdict["rubric_breakdown"] = breakdown
    verdict["status"] = "error" if status == "failed" else "ok"
    verdict_path.write_text(_json_text(verdict), encoding="utf-8")

    run_source["status"] = status
    run_source["score"] = {
        "raw": raw_score,
        "normalized": normalized_score,
        "scorer_version": "bbh-v0.1",
    }
    run_source_path.write_text(_json_text(run_source), encoding="utf-8")

    report_path.write_text(
        (
            "<html><body>"
            f"<h1>BBH score</h1><p>Decision: {decision}</p>"
            f"<p>Raw score: {raw_score:.4f}</p>"
            f"<p>Normalized score: {normalized_score:.4f}</p>"
            "</body></html>\n"
        ),
        encoding="utf-8",
    )

    score_path.write_text(
        _json_text(
            {
                "decision": decision,
                "status": status,
                "raw_score": raw_score,
                "normalized_score": normalized_score,
                "rubric_breakdown": breakdown,
            }
        ),
        encoding="utf-8",
    )

    return ScoreResult(
        decision=decision,
        justification=justification,
        raw_score=raw_score,
        normalized_score=normalized_score,
        rubric_breakdown=breakdown,
        status=status,
        verdict_path=verdict_path,
    )
