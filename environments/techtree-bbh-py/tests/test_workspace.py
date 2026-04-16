import json
from pathlib import Path

from jsonschema import validate

from techtree_bbh_py.datasets import load_split_rows
from techtree_bbh_py.materialize import materialize_workspace


def _schema(name: str) -> dict:
    root = Path(__file__).resolve().parents[3]
    return json.loads((root / "core" / "schemas" / name).read_text(encoding="utf-8"))


def test_materialize_workspace_writes_required_v01_contract(tmp_path: Path) -> None:
    capsule = load_split_rows("benchmark", task_ids=["benchmark-001"])[0]
    workspace = materialize_workspace(capsule, tmp_path / "workspace")

    assert workspace.artifact_source_path is not None
    assert workspace.genome_source_path.exists()
    assert workspace.run_source_path.exists()
    assert workspace.search_config_path is not None
    assert workspace.search_config_path.exists()
    assert workspace.evaluator_py_path is not None
    assert workspace.evaluator_py_path.exists()
    assert workspace.seed_program_path is not None
    assert workspace.seed_program_path.exists()
    assert workspace.best_program_path is not None
    assert workspace.best_program_path.exists()
    assert workspace.search_summary_json_path is not None
    assert workspace.search_summary_json_path.exists()
    assert workspace.evaluator_artifacts_json_path is not None
    assert workspace.evaluator_artifacts_json_path.exists()
    assert workspace.checkpoint_pointer_path is not None
    assert workspace.checkpoint_pointer_path.exists()
    assert workspace.best_solution_patch_path is not None
    assert workspace.best_solution_patch_path.exists()
    assert workspace.search_log_path is not None
    assert workspace.search_log_path.exists()
    assert workspace.task_json_path.exists()
    assert workspace.protocol_md_path.exists()
    assert workspace.rubric_json_path.exists()
    assert workspace.analysis_py_path.exists()
    assert workspace.final_answer_md_path.exists()
    assert workspace.verdict_json_path.exists()
    assert workspace.run_log_path.exists()
    assert workspace.dist_dir.exists()
    assert (workspace.data_dir / "outcomes.csv").exists()

    notebook = workspace.analysis_py_path.read_text(encoding="utf-8")
    assert "import marimo" in notebook
    assert "task.json" in notebook
    assert "protocol.md" in notebook

    artifact_source = json.loads(workspace.artifact_source_path.read_text(encoding="utf-8"))
    genome_source = json.loads(workspace.genome_source_path.read_text(encoding="utf-8"))
    run_source = json.loads(workspace.run_source_path.read_text(encoding="utf-8"))
    search_config = json.loads(workspace.search_config_path.read_text(encoding="utf-8"))
    search_summary = json.loads(workspace.search_summary_json_path.read_text(encoding="utf-8"))

    validate(artifact_source, _schema("techtree.bbh.artifact-source.v1.schema.json"))
    validate(genome_source, _schema("techtree.bbh.genome-source.v1.schema.json"))
    validate(run_source, _schema("techtree.bbh.run-source.v1.schema.json"))

    assert run_source["bbh"]["assignment_ref"] == "assign_benchmark-001"
    assert "skydiscover" in run_source["notes"]
    assert search_config["solver"]["kind"] == "skydiscover"
    assert search_summary["evaluator"]["kind"] == "hypotest"
    assert run_source["paths"]["verdict_path"] == "outputs/verdict.json"
    assert run_source["paths"]["search_summary_path"] == "outputs/skydiscover/search_summary.json"
    assert len(run_source["artifact_manifest"]) >= 2
