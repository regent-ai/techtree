from __future__ import annotations

import json
from hashlib import sha256
from pathlib import Path
from typing import Any

from .models import Capsule

SEARCH_CONFIG_SCHEMA_VERSION = "techtree.bbh.search-config.v1"
SEARCH_SUMMARY_SCHEMA_VERSION = "techtree.bbh.search-summary.v1"
SKYDISCOVER_KIND = "skydiscover"
HYPOTEST_KIND = "hypotest"
DEFAULT_SEARCH_ALGORITHM = "best_of_n"
DEFAULT_SCORER_VERSION = "hypotest-v0.1"
SEARCH_SUMMARY_PATH = "outputs/skydiscover/search_summary.json"
SEARCH_LOG_PATH = "outputs/skydiscover/search.log"
BEST_PROGRAM_PATH = "outputs/skydiscover/best_program.py"
EVALUATOR_ARTIFACTS_PATH = "outputs/skydiscover/evaluator_artifacts.json"
CHECKPOINT_POINTER_PATH = "outputs/skydiscover/latest_checkpoint.txt"
BEST_SOLUTION_PATCH_PATH = "outputs/skydiscover/best_solution.patch"


def _json_text(value: object) -> str:
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def _stable_hash(value: object) -> str:
    return sha256(_json_text(value).encode("utf-8")).hexdigest()


def _rubric_lookup(capsule: Capsule) -> dict[str, float]:
    return {item.rubric_item_id: float(item.points_possible) for item in capsule.rubric}


def build_search_config(
    capsule: Capsule,
    genome_source: dict[str, object],
    *,
    workspace_dir: Path,
    solver_kind: str = SKYDISCOVER_KIND,
    search_algorithm: str = DEFAULT_SEARCH_ALGORITHM,
    evaluator_kind: str = HYPOTEST_KIND,
    scorer_version: str = DEFAULT_SCORER_VERSION,
) -> dict[str, Any]:
    genome_ref = str(genome_source.get("label") or capsule.capsule_id)
    dataset_ref = str(capsule.provider_ref or capsule.capsule_id)
    config = {
        "schema_version": SEARCH_CONFIG_SCHEMA_VERSION,
        "capsule": {
            "capsule_id": capsule.capsule_id,
            "split": capsule.split,
            "provider": capsule.provider,
            "provider_ref": capsule.provider_ref,
            "family_ref": capsule.family_ref,
            "instance_ref": capsule.instance_ref,
        },
        "solver": {
            "kind": solver_kind,
            "entrypoint": "techtree_bbh_py.integrations:run_search",
        },
        "search": {
            "algorithm": search_algorithm,
            "budget": {
                "attempts": 1,
                "max_turns": 20,
            },
            "checkpoint_ref": None,
            "summary_ref": SEARCH_SUMMARY_PATH,
        },
        "evaluator": {
            "kind": evaluator_kind,
            "dataset_ref": dataset_ref,
            "benchmark_ref": capsule.capsule_id,
            "scorer_version": scorer_version,
        },
        "genome": {
            "ref": genome_ref,
            "harness_type": genome_source.get("harness_type"),
            "harness_version": genome_source.get("harness_version"),
            "tool_profile": genome_source.get("tool_profile"),
        },
        "workspace": {
            "root": str(workspace_dir),
            "analysis_path": "analysis.py",
            "verdict_path": "outputs/verdict.json",
            "log_path": SEARCH_LOG_PATH,
        },
    }
    config["search"]["config_hash"] = f"sha256:{_stable_hash(config)}"
    return config


def build_search_summary(search_config: dict[str, Any]) -> dict[str, Any]:
    artifact_paths = {
        "config_path": "search.config.yaml",
        "summary_path": SEARCH_SUMMARY_PATH,
        "log_path": SEARCH_LOG_PATH,
        "best_program_path": BEST_PROGRAM_PATH,
        "evaluator_artifacts_path": EVALUATOR_ARTIFACTS_PATH,
        "checkpoint_pointer_path": CHECKPOINT_POINTER_PATH,
        "best_solution_patch_path": BEST_SOLUTION_PATCH_PATH,
        "verdict_path": "outputs/verdict.json",
    }

    return {
        "schema_version": SEARCH_SUMMARY_SCHEMA_VERSION,
        "best_score": 0.0,
        "best_iteration": 0,
        "iterations_requested": int(search_config["search"]["budget"]["attempts"]),
        "iterations_completed": 0,
        "total_evaluations": 0,
        "elapsed_ms": 0,
        "checkpoint_ref": search_config["search"]["checkpoint_ref"],
        "artifact_keys": list(artifact_paths.keys()),
        "solver": search_config["solver"],
        "search": search_config["search"],
        "evaluator": search_config["evaluator"],
        "capsule": search_config["capsule"],
        "workspace": search_config["workspace"],
        "artifacts": artifact_paths,
        "search_hash": f"sha256:{_stable_hash(search_config)}",
    }


def build_search_log(search_summary: dict[str, Any]) -> str:
    solver = search_summary["solver"]
    search = search_summary["search"]
    evaluator = search_summary["evaluator"]
    capsule = search_summary["capsule"]
    workspace = search_summary["workspace"]
    lines = [
        "SkyDiscover search prepared",
        f"capsule: {capsule['capsule_id']}",
        f"solver: {solver['kind']}",
        f"algorithm: {search['algorithm']}",
        f"evaluator: {evaluator['kind']}",
        f"dataset_ref: {evaluator['dataset_ref']}",
        f"workspace: {workspace['root']}",
    ]
    return "\n".join(lines) + "\n"


def build_evaluator_artifacts(capsule: Capsule, search_summary: dict[str, Any]) -> dict[str, Any]:
    return {
        "schema_version": "techtree.bbh.evaluator-artifacts.v1",
        "capsule_id": capsule.capsule_id,
        "dataset_ref": search_summary["evaluator"]["dataset_ref"],
        "combined_score": search_summary["best_score"],
        "artifacts": [],
    }


def build_seed_program(capsule: Capsule) -> str:
    return (
        '"""Seed program for SkyDiscover BBH search."""\n\n'
        f'CAPSULE_ID = "{capsule.capsule_id}"\n\n'
        "# EVOLVE-BLOCK START\n"
        "def solve(task):\n"
        '    return {"status": "pending", "capsule_id": CAPSULE_ID, "task": task}\n'
        "# EVOLVE-BLOCK END\n"
    )


def build_evaluator_shim() -> str:
    return (
        '"""Hypotest adapter shim for SkyDiscover BBH workspaces."""\n\n'
        "def evaluate(candidate_program_path, dataset_ref, capsule_data_ref=None):\n"
        '    return {"combined_score": 0.0, "artifacts": []}\n'
    )


def build_seed_hypotest_output(
    capsule: Capsule,
    search_summary: dict[str, Any],
) -> dict[str, Any]:
    rubric_lookup = _rubric_lookup(capsule)
    return {
        "schema_version": "hypotest.result.v1",
        "final_decision": "support",
        "summary": "SkyDiscover seeded a placeholder Hypotest result for local workspace materialization.",
        "score": {"raw": 0.0, "normalized": 0.0},
        "rubric_claims": [
            {
                "rubric_item_id": item.rubric_item_id,
                "satisfied": False,
                "points_possible": rubric_lookup[item.rubric_item_id],
                "evidence": "Seeded by techtree-bbh-py.",
            }
            for item in capsule.rubric
        ],
        "evaluator": {
            "kind": search_summary["evaluator"]["kind"],
            "dataset_ref": search_summary["evaluator"]["dataset_ref"],
            "scorer_version": search_summary["evaluator"]["scorer_version"],
        },
        "search_hash": search_summary["search_hash"],
        "status": "ok",
    }


def _normalise_breakdown_item(item: dict[str, Any], rubric_lookup: dict[str, float]) -> dict[str, Any]:
    rubric_item_id = str(item.get("rubric_item_id") or item.get("id") or "unknown")
    points_possible = float(item.get("points_possible") or rubric_lookup.get(rubric_item_id, 0.0))
    if "points_awarded" in item and isinstance(item["points_awarded"], (int, float)):
        points_awarded = float(item["points_awarded"])
    elif bool(item.get("satisfied")):
        points_awarded = points_possible
    else:
        points_awarded = 0.0
    return {
        "rubric_item_id": rubric_item_id,
        "points_awarded": points_awarded,
        "points_possible": points_possible,
        "notes": item.get("notes") or item.get("evidence"),
    }


def normalise_hypotest_output(
    raw_result: dict[str, Any],
    rubric_items: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    rubric_items = rubric_items or []
    if {"decision", "justification", "metrics", "rubric_breakdown"}.issubset(raw_result.keys()):
        metrics = raw_result.get("metrics") if isinstance(raw_result.get("metrics"), dict) else {}
        return {
            "decision": str(raw_result.get("decision") or "inconclusive"),
            "justification": str(raw_result.get("justification") or ""),
            "metrics": {
                "raw_score": float(metrics.get("raw_score") or 0.0),
                "normalized_score": float(metrics.get("normalized_score") or 0.0),
            },
            "rubric_breakdown": [
                _normalise_breakdown_item(
                    item,
                    {
                        str(rubric_item.get("rubric_item_id") or "unknown"): float(
                            rubric_item.get("points_possible") or 0.0
                        )
                        for rubric_item in rubric_items
                    },
                )
                for item in raw_result.get("rubric_breakdown", [])
                if isinstance(item, dict)
            ],
            "status": str(raw_result.get("status") or "ok"),
        }

    rubric_lookup = {
        str(rubric_item.get("rubric_item_id") or "unknown"): float(rubric_item.get("points_possible") or 0.0)
        for rubric_item in rubric_items
    }
    rubric_claims = [item for item in raw_result.get("rubric_claims", []) if isinstance(item, dict)]
    breakdown = [_normalise_breakdown_item(item, rubric_lookup) for item in rubric_claims]
    if not breakdown:
        for item in rubric_items:
            breakdown.append(
                {
                    "rubric_item_id": str(item.get("rubric_item_id") or "unknown"),
                    "points_awarded": 0.0,
                    "points_possible": float(item.get("points_possible") or 0.0),
                    "notes": "Synthesized from missing Hypotest rubric claims.",
                }
            )

    raw_score = sum(float(item["points_awarded"]) for item in breakdown)
    max_score = sum(float(item["points_possible"]) for item in breakdown)
    metrics = raw_result.get("score") if isinstance(raw_result.get("score"), dict) else {}
    normalized_score = metrics.get("normalized")
    if not isinstance(normalized_score, (int, float)):
        normalized_score = 0.0 if max_score <= 0 else raw_score / max_score

    return {
        "decision": str(raw_result.get("final_decision") or raw_result.get("decision") or "inconclusive"),
        "justification": str(
            raw_result.get("summary")
            or raw_result.get("justification")
            or raw_result.get("reason")
            or ""
        ),
        "metrics": {
            "raw_score": float(metrics.get("raw") if isinstance(metrics.get("raw"), (int, float)) else raw_score),
            "normalized_score": float(normalized_score),
        },
        "rubric_breakdown": breakdown,
        "status": str(raw_result.get("status") or "ok"),
    }


def build_run_provenance_note(search_config: dict[str, Any], search_summary: dict[str, Any]) -> str:
    payload = {
        "solver": search_config["solver"],
        "search": search_config["search"],
        "evaluator": search_config["evaluator"],
        "artifacts": search_summary["artifacts"],
        "search_hash": search_summary["search_hash"],
    }
    return _json_text(payload).strip()


def build_review_provenance_note(
    search_config: dict[str, Any],
    search_summary: dict[str, Any],
    *,
    result: str,
    reproduced_raw_score: float,
    reproduced_normalized_score: float,
    tolerance: float,
) -> str:
    payload = {
        "solver": search_config["solver"],
        "search": search_config["search"],
        "evaluator": search_config["evaluator"],
        "artifacts": search_summary["artifacts"],
        "result": result,
        "reproduced": {
            "raw_score": reproduced_raw_score,
            "normalized_score": reproduced_normalized_score,
        },
        "tolerance": tolerance,
        "search_hash": search_summary["search_hash"],
    }
    return _json_text(payload).strip()


def build_evidence_refs() -> list[dict[str, Any]]:
    return [
        {"kind": "file", "ref": "search.config.yaml", "note": "SkyDiscover search configuration."},
        {"kind": "file", "ref": SEARCH_SUMMARY_PATH, "note": "Prepared search summary."},
        {"kind": "file", "ref": SEARCH_LOG_PATH, "note": "Search log."},
        {"kind": "file", "ref": BEST_PROGRAM_PATH, "note": "Best discovered program."},
        {"kind": "file", "ref": EVALUATOR_ARTIFACTS_PATH, "note": "Normalized evaluator artifacts."},
        {"kind": "file", "ref": "outputs/verdict.json", "note": "Canonical verdict after normalization."},
    ]


def run_search(
    capsule: Capsule,
    genome_source: dict[str, object],
    *,
    workspace_dir: Path,
    solver_kind: str = SKYDISCOVER_KIND,
    search_algorithm: str = DEFAULT_SEARCH_ALGORITHM,
    evaluator_kind: str = HYPOTEST_KIND,
    scorer_version: str = DEFAULT_SCORER_VERSION,
) -> dict[str, Any]:
    search_config = build_search_config(
        capsule,
        genome_source,
        workspace_dir=workspace_dir,
        solver_kind=solver_kind,
        search_algorithm=search_algorithm,
        evaluator_kind=evaluator_kind,
        scorer_version=scorer_version,
    )
    search_summary = build_search_summary(search_config)
    search_log = build_search_log(search_summary)
    (workspace_dir / "search.config.yaml").write_text(_json_text(search_config), encoding="utf-8")
    (workspace_dir / "outputs" / "skydiscover").mkdir(parents=True, exist_ok=True)
    (workspace_dir / SEARCH_SUMMARY_PATH).write_text(_json_text(search_summary), encoding="utf-8")
    (workspace_dir / "outputs").mkdir(parents=True, exist_ok=True)
    (workspace_dir / SEARCH_LOG_PATH).write_text(search_log, encoding="utf-8")
    return {
        "search_config": search_config,
        "search_summary": search_summary,
        "search_log": search_log,
    }
