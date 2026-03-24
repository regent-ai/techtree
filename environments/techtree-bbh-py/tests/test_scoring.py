import json
from pathlib import Path

from techtree_bbh_py.datasets import load_split_rows
from techtree_bbh_py.materialize import materialize_workspace
from techtree_bbh_py.score import score_workspace
from techtree_bbh_py.validate import validate_workspace


def _write_verdict(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def test_score_workspace_updates_fixed_run_and_report(tmp_path: Path) -> None:
    capsule = load_split_rows("climb", task_ids=["climb-001"])[0]
    workspace = materialize_workspace(capsule, tmp_path / "fixed")
    _write_verdict(
        workspace.verdict_json_path,
        {
            "decision": "support",
            "justification": "The values increase across the measurements.",
            "metrics": {"raw_score": 7.0, "normalized_score": 1.0},
            "rubric_breakdown": [
                {"rubric_item_id": "summary", "points_awarded": 2, "points_possible": 2},
                {"rubric_item_id": "final_objective", "points_awarded": 5, "points_possible": 5},
            ],
            "status": "ok",
        },
    )

    result = score_workspace(workspace.workspace_dir)
    run_source = json.loads(workspace.run_source_path.read_text(encoding="utf-8"))

    assert result.status == "completed"
    assert result.raw_score == 7.0
    assert result.normalized_score == 1.0
    assert run_source["status"] == "completed"
    assert run_source["score"]["raw"] == 7.0
    assert workspace.report_html_path.exists()


def test_score_workspace_handles_family_capsules(tmp_path: Path) -> None:
    capsule = load_split_rows("challenge", task_ids=["challenge-family-001"])[0]
    workspace = materialize_workspace(capsule, tmp_path / "family")
    _write_verdict(
        workspace.verdict_json_path,
        {
            "decision": "reject",
            "justification": "The synthetic family instance does not meet the hypothesis.",
            "rubric_breakdown": [
                {"rubric_item_id": "dose_response", "points_awarded": 2, "points_possible": 3},
                {"rubric_item_id": "final_objective", "points_awarded": 5, "points_possible": 5},
            ],
            "status": "ok",
        },
    )

    result = score_workspace(workspace.workspace_dir)

    assert result.status == "completed"
    assert result.raw_score == 7.0
    assert 0.0 <= result.normalized_score <= 1.0


def test_replay_validation_recomputes_score_within_tolerance(tmp_path: Path) -> None:
    capsule = load_split_rows("benchmark", task_ids=["benchmark-002"])[0]
    workspace = materialize_workspace(capsule, tmp_path / "replay")
    _write_verdict(
        workspace.verdict_json_path,
        {
            "decision": "support",
            "justification": "The values trend upward.",
            "metrics": {"raw_score": 7.0, "normalized_score": 1.0},
            "rubric_breakdown": [
                {"rubric_item_id": "trend", "points_awarded": 2, "points_possible": 2},
                {"rubric_item_id": "final_objective", "points_awarded": 5, "points_possible": 5},
            ],
            "status": "ok",
        },
    )

    score_workspace(workspace.workspace_dir)
    validation = validate_workspace(workspace.workspace_dir, run_id="run_benchmark_002")
    review_source = json.loads(validation.review_source_path.read_text(encoding="utf-8"))

    assert validation.matches is True
    assert validation.result == "confirmed"
    assert review_source["method"] == "replay"
    assert review_source["bbh"]["role"] == "official"
