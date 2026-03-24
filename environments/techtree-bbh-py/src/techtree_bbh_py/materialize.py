from __future__ import annotations

import json
import shutil
from hashlib import sha256
from importlib import resources
from pathlib import Path

from .models import BbhHarnessType, Capsule, MaterializedWorkspace

NOTEBOOK_TEMPLATE = resources.files("techtree_bbh_py.templates").joinpath("analysis.py").read_text(encoding="utf-8")
FINAL_ANSWER_TEMPLATE = resources.files("techtree_bbh_py.templates").joinpath("final_answer.md").read_text(encoding="utf-8")


def _json_text(value: object) -> str:
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def _write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


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
) -> MaterializedWorkspace:
    if workspace_dir.exists():
        shutil.rmtree(workspace_dir)
    workspace_dir.mkdir(parents=True, exist_ok=True)

    outputs_dir = workspace_dir / "outputs"
    data_dir = workspace_dir / "data"
    dist_dir = workspace_dir / "dist"
    outputs_dir.mkdir(parents=True, exist_ok=True)
    data_dir.mkdir(parents=True, exist_ok=True)
    dist_dir.mkdir(parents=True, exist_ok=True)

    artifact_source_path = workspace_dir / "artifact.source.yaml"
    genome_source_path = workspace_dir / "genome.source.yaml"
    run_source_path = workspace_dir / "run.source.yaml"
    task_json_path = workspace_dir / "task.json"
    protocol_md_path = workspace_dir / "protocol.md"
    rubric_json_path = workspace_dir / "rubric.json"
    analysis_py_path = workspace_dir / "analysis.py"
    final_answer_md_path = workspace_dir / "final_answer.md"
    verdict_json_path = outputs_dir / "verdict.json"
    report_html_path = outputs_dir / "report.html"
    run_log_path = outputs_dir / "run.log"

    resolved_genome = genome_source or _deterministic_genome(capsule, harness_type)
    resolved_assignment_ref = assignment_ref if assignment_ref is not None else (
        f"assign_{capsule.capsule_id}" if capsule.split in {"benchmark", "challenge"} else None
    )

    genome_ref = _genome_ref(resolved_genome)

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
            "notes": None,
        },
        "notes": None,
    }

    _write_text(artifact_source_path, _json_text(capsule.artifact_source_payload()))
    _write_text(genome_source_path, _json_text(resolved_genome))
    _write_text(run_source_path, _json_text(run_source))
    _write_text(task_json_path, _json_text(capsule.task_payload()))
    _write_text(protocol_md_path, capsule.protocol_markdown())
    _write_text(rubric_json_path, _json_text(capsule.rubric_payload()))
    _write_text(analysis_py_path, NOTEBOOK_TEMPLATE)
    _write_text(final_answer_md_path, FINAL_ANSWER_TEMPLATE)
    _write_text(
        verdict_json_path,
        _json_text(
            {
                "decision": "inconclusive",
                "justification": "Pending notebook execution.",
                "metrics": {"raw_score": 0.0, "normalized_score": 0.0},
                "rubric_breakdown": [],
                "status": "ok",
            }
        ),
    )
    _write_text(run_log_path, "")

    for item in capsule.data_files:
        _write_text(data_dir / item.name, item.content)

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
    )
