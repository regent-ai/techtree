from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Sequence

from .datasets import load_split_rows
from .materialize import materialize_workspace
from .models import BbhHarnessType, Capsule, MaterializedWorkspace, ScoreResult, ValidationResult
from .score import score_workspace
from .validate import validate_workspace


def _json_text(value: object) -> str:
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def _default_workspace_root(split: str) -> Path:
    return Path.cwd() / ".techtree-bbh" / split


def _default_genome(capsule: Capsule, harness_type: BbhHarnessType) -> dict[str, object]:
    return {
        "schema_version": "techtree.bbh.genome-source.v1",
        "label": f"{capsule.provider}:{capsule.capsule_id}",
        "model_id": "local-debug-model",
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


def _default_verdict(capsule: Capsule) -> dict[str, Any]:
    rubric_breakdown: list[dict[str, Any]] = []
    total_points = 0.0
    awarded_points = 0.0
    for item in capsule.rubric:
        total_points += float(item.points_possible)
        points_awarded = float(item.points_possible) if item.rubric_item_id == "final_objective" else 0.0
        awarded_points += points_awarded
        rubric_breakdown.append(
            {
                "rubric_item_id": item.rubric_item_id,
                "points_awarded": points_awarded,
                "points_possible": float(item.points_possible),
                "notes": "Seeded by techtree-bbh smoke mode.",
            }
        )
    normalized = 0.0 if total_points <= 0 else min(1.0, awarded_points / total_points)
    return {
        "decision": "support",
        "justification": "Smoke mode generated a deterministic placeholder verdict for local validation.",
        "metrics": {
            "raw_score": awarded_points,
            "normalized_score": normalized,
        },
        "rubric_breakdown": rubric_breakdown,
        "status": "ok",
    }


@dataclass(slots=True)
class BbhPyEnvironment:
    split: str
    capsules: list[Capsule]
    official_mode: bool = False
    workspace_root: Path | None = None
    public_dataset: str | None = None
    problem_jsonl: str | None = None
    metadata: dict[str, str] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if self.workspace_root is not None:
            self.workspace_root = self.workspace_root.expanduser()

    def get_capsule(self, capsule_id: str | None = None) -> Capsule:
        if capsule_id is None:
            return self.capsules[0]
        for capsule in self.capsules:
            if capsule.capsule_id == capsule_id:
                return capsule
        raise KeyError(f"unknown capsule: {capsule_id}")

    def materialize(
        self,
        capsule_id: str | None = None,
        *,
        workspace_dir: Path | None = None,
        genome_source: dict[str, object] | None = None,
        assignment_ref: str | None = None,
        harness_type: BbhHarnessType = "openclaw",
    ) -> MaterializedWorkspace:
        capsule = self.get_capsule(capsule_id)
        target_workspace = workspace_dir or self.default_workspace_dir(capsule)
        resolved_genome = genome_source or _default_genome(capsule, harness_type)
        resolved_assignment_ref = assignment_ref if assignment_ref is not None else (
            f"assign_{capsule.capsule_id}" if capsule.split in {"benchmark", "challenge"} else None
        )
        return materialize_workspace(
            capsule,
            target_workspace,
            genome_source=resolved_genome,
            assignment_ref=resolved_assignment_ref,
            harness_type=harness_type,
        )

    def score(self, workspace_dir: Path) -> ScoreResult:
        return score_workspace(workspace_dir)

    def validate(self, workspace_dir: Path, *, run_id: str | None = None) -> ValidationResult:
        return validate_workspace(workspace_dir, run_id=run_id)

    def smoke(
        self,
        *,
        capsule_id: str | None = None,
        workspace_dir: Path | None = None,
        assignment_ref: str | None = None,
        harness_type: BbhHarnessType = "openclaw",
    ) -> dict[str, object]:
        workspace = self.materialize(
            capsule_id,
            workspace_dir=workspace_dir,
            assignment_ref=assignment_ref,
            harness_type=harness_type,
        )
        verdict_payload = _default_verdict(workspace.capsule)
        workspace.verdict_json_path.write_text(_json_text(verdict_payload), encoding="utf-8")
        workspace.final_answer_md_path.write_text(
            f"# Final answer\n\n{verdict_payload['justification']}\n",
            encoding="utf-8",
        )
        score = self.score(workspace.workspace_dir)
        validation = self.validate(workspace.workspace_dir, run_id=workspace.workspace_dir.name)
        return {
            "workspace_dir": str(workspace.workspace_dir),
            "capsule_id": workspace.capsule.capsule_id,
            "split": workspace.capsule.split,
            "score": {
                "raw": score.raw_score,
                "normalized": score.normalized_score,
                "status": score.status,
            },
            "validation": {
                "result": validation.result,
                "matches": validation.matches,
            },
        }

    def default_workspace_dir(self, capsule: Capsule) -> Path:
        base = self.workspace_root or _default_workspace_root(self.split)
        return base / capsule.capsule_id


def load_environment(
    *,
    split: str = "climb",
    task_ids: Sequence[str] | None = None,
    public_dataset: str | None = None,
    problem_jsonl: str | None = None,
    workspace_root: str | None = None,
    official_mode: bool = False,
    **_: object,
) -> BbhPyEnvironment:
    if split not in {"climb", "benchmark", "challenge", "draft"}:
        raise ValueError(f"unsupported split: {split}")

    capsules = load_split_rows(
        split,
        task_ids=task_ids,
        public_dataset=public_dataset,
        problem_jsonl=problem_jsonl,
    )
    if not capsules:
        raise ValueError(f"no Python capsules found for split={split}")

    return BbhPyEnvironment(
        split=split,
        capsules=capsules,
        official_mode=official_mode,
        workspace_root=Path(workspace_root) if workspace_root else None,
        public_dataset=public_dataset,
        problem_jsonl=problem_jsonl,
        metadata={"source": public_dataset or problem_jsonl or f"techtree-bbh-py/{split}"},
    )
