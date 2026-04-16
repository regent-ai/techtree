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
            "schema_version": "hypotest.result.v1",
            "final_decision": "support",
            "summary": "The values increase across the measurements.",
            "score": {"raw": 7.0, "normalized": 1.0},
            "rubric_claims": [
                {"rubric_item_id": "summary", "satisfied": True, "points_possible": 2},
                {"rubric_item_id": "final_objective", "satisfied": True, "points_possible": 5},
            ],
            "status": "ok",
        },
    )

    result = score_workspace(workspace.workspace_dir)
    verdict = json.loads(workspace.verdict_json_path.read_text(encoding="utf-8"))
    run_source = json.loads(workspace.run_source_path.read_text(encoding="utf-8"))

    assert result.status == "completed"
    assert result.raw_score == 7.0
    assert result.normalized_score == 1.0
    assert verdict["decision"] == "support"
    assert "rubric_breakdown" in verdict
    assert run_source["status"] == "completed"
    assert run_source["score"]["raw"] == 7.0
    assert run_source["score"]["scorer_version"] == "hypotest-v0.1"
    assert "solver" in run_source["notes"]
    assert workspace.report_html_path.exists()


def test_score_workspace_handles_family_capsules(tmp_path: Path) -> None:
    capsule = load_split_rows("challenge", task_ids=["challenge-family-001"])[0]
    workspace = materialize_workspace(capsule, tmp_path / "family")
    _write_verdict(
        workspace.verdict_json_path,
        {
            "schema_version": "hypotest.result.v1",
            "final_decision": "reject",
            "summary": "The synthetic family instance does not meet the hypothesis.",
            "score": {"raw": 7.0, "normalized": 0.875},
            "rubric_claims": [
                {"rubric_item_id": "dose_response", "satisfied": True, "points_possible": 3},
                {"rubric_item_id": "final_objective", "satisfied": True, "points_possible": 5},
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
    assert review_source["bbh"]["scorer_version"] == "hypotest-v0.1"
    assert "search.config.yaml" in {item["ref"] for item in review_source["evidence"]}
    assert "outputs/skydiscover/search_summary.json" in {item["ref"] for item in review_source["evidence"]}
    assert review_source["bbh"]["score_match"] is True
    assert review_source["bbh"]["artifact_match"] is True
    assert review_source["bbh"]["submitted_program_sha256"].startswith("sha256:")
    assert "evaluator" in review_source["notes"]


def test_replay_validation_detects_changed_best_program(tmp_path: Path) -> None:
    capsule = load_split_rows("benchmark", task_ids=["benchmark-002"])[0]
    workspace = materialize_workspace(capsule, tmp_path / "replay-mismatch")
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
    workspace.best_program_path.write_text("# changed after scoring\n", encoding="utf-8")

    validation = validate_workspace(workspace.workspace_dir, run_id="run_benchmark_002")
    review_source = json.loads(validation.review_source_path.read_text(encoding="utf-8"))

    assert validation.matches is True
    assert validation.artifact_match is False
    assert review_source["bbh"]["artifact_match"] is False
    assert (
        review_source["bbh"]["submitted_program_sha256"]
        != review_source["bbh"]["reproduced_program_sha256"]
    )
