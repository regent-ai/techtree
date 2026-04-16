from __future__ import annotations

import json
import shutil
from hashlib import sha256
from importlib import resources
from pathlib import Path

from .integrations import (
    BEST_PROGRAM_PATH,
    BEST_SOLUTION_PATCH_PATH,
    CHECKPOINT_POINTER_PATH,
    EVALUATOR_ARTIFACTS_PATH,
    SEARCH_LOG_PATH,
    SEARCH_SUMMARY_PATH,
    build_run_provenance_note,
    build_evaluator_artifacts,
    build_evaluator_shim,
    build_search_config,
    build_search_log,
    build_search_summary,
    build_seed_program,
    build_seed_hypotest_output,
)
from .models import BbhHarnessType, Capsule, MaterializedWorkspace

NOTEBOOK_TEMPLATE = resources.files("techtree_bbh_py.templates").joinpath("analysis.py").read_text(encoding="utf-8")
FINAL_ANSWER_TEMPLATE = resources.files("techtree_bbh_py.templates").joinpath("final_answer.md").read_text(encoding="utf-8")


def _json_text(value: object) -> str:
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def _write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def _sha256_path(path: Path) -> str:
    return f"sha256:{sha256(path.read_bytes()).hexdigest()}"


def _artifact_manifest_entry(
    path: Path,
    workspace_dir: Path,
    *,
    kind: str,
    required_for_validation: bool,
) -> dict[str, object]:
    return {
        "path": path.relative_to(workspace_dir).as_posix(),
        "kind": kind,
        "sha256": _sha256_path(path),
        "size_bytes": path.stat().st_size,
        "required_for_validation": required_for_validation,
    }


def _deterministic_genome(capsule: Capsule, harness_type: BbhHarnessType = "openclaw") -> dict[str, object]:
    payload = {
        "schema_version": "techtree.bbh.genome-source.v1",
        "label": f"{capsule.provider}:{capsule.capsule_id}",
        "model_id": "placeholder-model",
        "harness_type": harness_type,
        "harness_version": "local",
        "prompt_pack_version": "bbh-v0.1",
        "skill_pack_version": "techtree-bbh-v0.1",
        "tool_profile": "bbh",
        "runtime_image": "local-runtime",
        "helper_code_hash": None,
        "data_profile": "python-only",
        "axes": {},
        "notes": None,
    }
    return payload


def _genome_ref(genome_source: dict[str, object]) -> str:
    digest = sha256(_json_text(genome_source).encode("utf-8")).hexdigest()[:16]
    return f"gen_{digest}"


def materialize_workspace(
    capsule: Capsule,
    workspace_dir: Path,
    *,
    genome_source: dict[str, object] | None = None,
    assignment_ref: str | None = None,
    harness_type: BbhHarnessType = "openclaw",
    solver_kind: str = "skydiscover",
    search_algorithm: str = "best_of_n",
    evaluator_kind: str = "hypotest",
    scorer_version: str = "hypotest-v0.1",
) -> MaterializedWorkspace:
    if workspace_dir.exists():
        shutil.rmtree(workspace_dir)
    workspace_dir.mkdir(parents=True, exist_ok=True)

    outputs_dir = workspace_dir / "outputs"
    skydiscover_dir = outputs_dir / "skydiscover"
    data_dir = workspace_dir / "data"
    dist_dir = workspace_dir / "dist"
    eval_dir = workspace_dir / "eval"
    solver_dir = workspace_dir / "solver"
    outputs_dir.mkdir(parents=True, exist_ok=True)
    skydiscover_dir.mkdir(parents=True, exist_ok=True)
    data_dir.mkdir(parents=True, exist_ok=True)
    dist_dir.mkdir(parents=True, exist_ok=True)
    eval_dir.mkdir(parents=True, exist_ok=True)
    solver_dir.mkdir(parents=True, exist_ok=True)

    artifact_source_path = workspace_dir / "artifact.source.yaml"
    genome_source_path = workspace_dir / "genome.source.yaml"
    run_source_path = workspace_dir / "run.source.yaml"
    search_config_path = workspace_dir / "search.config.yaml"
    evaluator_py_path = eval_dir / "hypotest_skydiscover.py"
    seed_program_path = solver_dir / "initial_program.py"
    task_json_path = workspace_dir / "task.json"
    protocol_md_path = workspace_dir / "protocol.md"
    rubric_json_path = workspace_dir / "rubric.json"
    analysis_py_path = workspace_dir / "analysis.py"
    final_answer_md_path = workspace_dir / "final_answer.md"
    verdict_json_path = outputs_dir / "verdict.json"
    report_html_path = outputs_dir / "report.html"
    run_log_path = outputs_dir / "run.log"
    search_log_path = workspace_dir / SEARCH_LOG_PATH
    best_program_path = workspace_dir / BEST_PROGRAM_PATH
    search_summary_json_path = workspace_dir / SEARCH_SUMMARY_PATH
    evaluator_artifacts_json_path = workspace_dir / EVALUATOR_ARTIFACTS_PATH
    checkpoint_pointer_path = workspace_dir / CHECKPOINT_POINTER_PATH
    best_solution_patch_path = workspace_dir / BEST_SOLUTION_PATCH_PATH

    resolved_genome = genome_source or _deterministic_genome(capsule, harness_type)
    resolved_assignment_ref = assignment_ref if assignment_ref is not None else (
        f"assign_{capsule.capsule_id}" if capsule.split in {"benchmark", "challenge"} else None
    )

    genome_ref = _genome_ref(resolved_genome)
    search_config = build_search_config(
        capsule,
        resolved_genome,
        workspace_dir=workspace_dir,
        solver_kind=solver_kind,
        search_algorithm=search_algorithm,
        evaluator_kind=evaluator_kind,
        scorer_version=scorer_version,
    )
    search_summary = build_search_summary(search_config)
    seed_verdict = build_seed_hypotest_output(capsule, search_summary)
    provenance_note = build_run_provenance_note(search_config, search_summary)
    evaluator_artifacts = build_evaluator_artifacts(capsule, search_summary)
    seed_program = build_seed_program(capsule)
    evaluator_shim = build_evaluator_shim()

    # The materialized workspace is the canonical handoff between BBH notebook work,
    # SkyDiscover search metadata, and the Hypotest scorer/replay story.
    run_source = {
        "schema_version": "techtree.bbh.run-source.v1",
        "artifact_ref": capsule.capsule_id,
        "executor": {
            "type": "genome",
            "id": genome_ref,
            "harness": resolved_genome["harness_type"],
            "harness_version": resolved_genome["harness_version"],
            "profile": resolved_genome["tool_profile"],
        },
        "solver": {
            "kind": solver_kind,
            "entrypoint": str(search_config["solver"]["entrypoint"]),
        },
        "search": {
            "algorithm": search_algorithm,
            "budget": int(search_config["search"]["budget"]["attempts"]),
            "checkpoint_ref": None,
            "summary": None,
        },
        "evaluator": {
            "kind": evaluator_kind,
            "dataset_ref": str(search_config["evaluator"]["dataset_ref"]),
            "benchmark_ref": str(search_config["evaluator"]["benchmark_ref"]),
            "scorer_version": scorer_version,
        },
        "instance": {
            "instance_ref": capsule.instance_ref or capsule.capsule_id,
            "family_ref": capsule.family_ref,
            "seed": None,
        },
        "origin": {
            "workload": "bbh",
            "transport": "local",
            "trigger": "manual",
        },
        "paths": {
            "analysis_path": "analysis.py",
            "verdict_path": "outputs/verdict.json",
            "final_answer_path": "final_answer.md",
            "report_path": "outputs/report.html",
            "log_path": "outputs/run.log",
            "genome_path": "genome.source.yaml",
            "search_config_path": "search.config.yaml",
            "evaluator_path": "eval/hypotest_skydiscover.py",
            "seed_program_path": "solver/initial_program.py",
            "best_program_path": BEST_PROGRAM_PATH,
            "search_summary_path": SEARCH_SUMMARY_PATH,
            "evaluator_artifacts_path": EVALUATOR_ARTIFACTS_PATH,
            "checkpoint_pointer_path": CHECKPOINT_POINTER_PATH,
            "best_solution_patch_path": BEST_SOLUTION_PATCH_PATH,
            "search_log_path": SEARCH_LOG_PATH,
        },
        "status": "created",
        "score": None,
        "bbh": {
            "split": capsule.split,
            "genome_ref": genome_ref,
            "provider": capsule.provider,
            "assignment_ref": resolved_assignment_ref,
            "keep_decision": "pending",
            "parent_genome_ref": None,
            "child_genome_ref": None,
            "notes": provenance_note,
        },
        "artifact_manifest": [],
        "notes": provenance_note,
    }

    _write_text(artifact_source_path, _json_text(capsule.artifact_source_payload()))
    _write_text(genome_source_path, _json_text(resolved_genome))
    _write_text(run_source_path, _json_text(run_source))
    _write_text(search_config_path, _json_text(search_config))
    _write_text(evaluator_py_path, evaluator_shim)
    _write_text(seed_program_path, seed_program)
    _write_text(best_program_path, seed_program)
    _write_text(search_summary_json_path, _json_text(search_summary))
    _write_text(evaluator_artifacts_json_path, _json_text(evaluator_artifacts))
    _write_text(checkpoint_pointer_path, "")
    _write_text(best_solution_patch_path, "")
    _write_text(search_log_path, build_search_log(search_summary))
    _write_text(task_json_path, _json_text(capsule.task_payload()))
    _write_text(protocol_md_path, capsule.protocol_markdown())
    _write_text(rubric_json_path, _json_text(capsule.rubric_payload()))
    _write_text(analysis_py_path, NOTEBOOK_TEMPLATE)
    _write_text(final_answer_md_path, FINAL_ANSWER_TEMPLATE)
    _write_text(verdict_json_path, _json_text(seed_verdict))
    _write_text(run_log_path, "")

    for item in capsule.data_files:
        _write_text(data_dir / item.name, item.content)

    artifact_manifest = [
        _artifact_manifest_entry(analysis_py_path, workspace_dir, kind="workspace_file", required_for_validation=False),
        _artifact_manifest_entry(search_config_path, workspace_dir, kind="workspace_file", required_for_validation=True),
        _artifact_manifest_entry(evaluator_py_path, workspace_dir, kind="workspace_file", required_for_validation=True),
        _artifact_manifest_entry(seed_program_path, workspace_dir, kind="workspace_file", required_for_validation=True),
        _artifact_manifest_entry(best_program_path, workspace_dir, kind="generated_output", required_for_validation=True),
        _artifact_manifest_entry(search_summary_json_path, workspace_dir, kind="generated_output", required_for_validation=True),
        _artifact_manifest_entry(evaluator_artifacts_json_path, workspace_dir, kind="generated_output", required_for_validation=True),
        _artifact_manifest_entry(checkpoint_pointer_path, workspace_dir, kind="checkpoint_pointer", required_for_validation=False),
        _artifact_manifest_entry(best_solution_patch_path, workspace_dir, kind="generated_output", required_for_validation=False),
        _artifact_manifest_entry(verdict_json_path, workspace_dir, kind="generated_output", required_for_validation=True),
    ]
    run_source["artifact_manifest"] = artifact_manifest
    _write_text(run_source_path, _json_text(run_source))

    return MaterializedWorkspace(
        capsule=capsule,
        workspace_dir=workspace_dir,
        artifact_source_path=artifact_source_path,
        genome_source_path=genome_source_path,
        run_source_path=run_source_path,
        task_json_path=task_json_path,
        protocol_md_path=protocol_md_path,
        rubric_json_path=rubric_json_path,
        analysis_py_path=analysis_py_path,
        final_answer_md_path=final_answer_md_path,
        verdict_json_path=verdict_json_path,
        report_html_path=report_html_path,
        run_log_path=run_log_path,
        data_dir=data_dir,
        dist_dir=dist_dir,
        search_config_path=search_config_path,
        evaluator_py_path=evaluator_py_path,
        seed_program_path=seed_program_path,
        best_program_path=best_program_path,
        search_summary_json_path=search_summary_json_path,
        evaluator_artifacts_json_path=evaluator_artifacts_json_path,
        checkpoint_pointer_path=checkpoint_pointer_path,
        best_solution_patch_path=best_solution_patch_path,
        search_log_path=search_log_path,
    )
