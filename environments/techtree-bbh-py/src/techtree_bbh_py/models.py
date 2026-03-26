from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Literal


BbhSplit = Literal["climb", "benchmark", "challenge", "draft"]
BbhMode = Literal["fixed", "family"]
BbhProvider = Literal["bbh", "bbh_train", "techtree"]
BbhAssignmentPolicy = Literal["auto", "select", "auto_or_select", "operator"]
BbhHarnessType = Literal["openclaw", "hermes", "claude_code", "custom"]


@dataclass(frozen=True, slots=True)
class DataFile:
    name: str
    content: str


@dataclass(frozen=True, slots=True)
class RubricItem:
    rubric_item_id: str
    description: str
    points_possible: int
    expected_output: str | None = None


@dataclass(frozen=True, slots=True)
class Capsule:
    capsule_id: str
    split: BbhSplit
    language: Literal["python"]
    mode: BbhMode
    provider: BbhProvider
    provider_ref: str
    family_ref: str | None
    instance_ref: str | None
    assignment_policy: BbhAssignmentPolicy
    title: str
    hypothesis: str
    protocol: tuple[str, ...]
    rubric: tuple[RubricItem, ...]
    data_files: tuple[DataFile, ...]
    raw: dict[str, Any] = field(repr=False, compare=False)

    def protocol_markdown(self) -> str:
        steps = "\n".join(f"{index}. {step}" for index, step in enumerate(self.protocol, start=1))
        return f"# {self.title}\n\n## Hypothesis\n{self.hypothesis}\n\n## Protocol\n{steps}\n"

    def task_payload(self) -> dict[str, Any]:
        return {
            "capsule_id": self.capsule_id,
            "split": self.split,
            "language": self.language,
            "mode": self.mode,
            "provider": self.provider,
            "provider_ref": self.provider_ref,
            "family_ref": self.family_ref,
            "instance_ref": self.instance_ref,
            "assignment_policy": self.assignment_policy,
            "title": self.title,
            "hypothesis": self.hypothesis,
            "data_refs": [{"path": f"data/{item.name}"} for item in self.data_files],
        }

    def rubric_payload(self) -> dict[str, Any]:
        return {
            "items": [
                {
                    "rubric_item_id": item.rubric_item_id,
                    "description": item.description,
                    "points_possible": item.points_possible,
                    "expected_output": item.expected_output,
                }
                for item in self.rubric
            ]
        }

    def artifact_source_payload(self) -> dict[str, Any]:
        return {
            "schema_version": "techtree.bbh.artifact-source.v1",
            "title": self.title,
            "summary": f"{self.provider} capsule {self.capsule_id}",
            "parents": [],
            "notebook": {
                "entrypoint": "analysis.py",
                "include": ["analysis.py", "protocol.md", "rubric.json", "task.json", "data/**/*"],
                "exclude": ["outputs/**", "dist/**"],
                "marimo_version": "0.13.0",
            },
            "env": {
                "lockfile_path": "uv.lock",
                "image": None,
                "system": {"python": "3.11", "platform": "linux/amd64"},
                "runtime_policy": {
                    "network": "none",
                    "filesystem": "workspace_write",
                    "secrets": "forbidden",
                    "gpu": False,
                },
            },
            "provenance": {"source_repo": None, "source_commit": None, "build_attestation_files": []},
            "claims": [],
            "notes": None,
            "sources": [],
            "licenses": {"notebook": None, "data": None, "outputs": None},
            "eval": {
                "mode": self.mode,
                "protocol": {
                    "entrypoint": "eval/run.py",
                    "allowed_tools": ["python"],
                    "max_runtime_s": 1800,
                    "max_turns": 20,
                    "output_contract": {
                        "required_files": ["outputs/verdict.json"],
                        "required_keys": ["decision", "justification", "metrics"],
                    },
                },
                "rubric": {
                    "scorer": "eval/score.py",
                    "primary_metric": "raw_score",
                    "secondary_metrics": ["normalized_score"],
                    "score_range": {"min": 0.0, "max": 10.0},
                    "aggregation": "deterministic",
                    "pass_rule": "see rubric.json",
                },
                **(
                    {}
                    if self.mode == "fixed"
                    else {
                        "generator": {
                            "entrypoint": "eval/generate.py",
                            "seed_type": "uint64",
                            "determinism": "seed_only",
                            "params_schema": "schemas/family.json",
                        }
                    }
                ),
            },
            "bbh": {
                "split": self.split,
                "language": self.language,
                "provider": self.provider,
                "provider_ref": self.provider_ref,
                "family_ref": self.family_ref,
                "instance_ref": self.instance_ref,
                "hypothesis": self.hypothesis,
                "protocol_path": "protocol.md",
                "rubric_path": "rubric.json",
                "data_refs": [{"path": f"data/{item.name}"} for item in self.data_files],
                "assignment_policy": self.assignment_policy,
                "difficulty": None,
                "tags": [],
                "source_paper_ref": None,
            },
        }


@dataclass(frozen=True, slots=True)
class MaterializedWorkspace:
    capsule: Capsule
    workspace_dir: Path
    artifact_source_path: Path | None
    genome_source_path: Path
    run_source_path: Path
    task_json_path: Path
    protocol_md_path: Path
    rubric_json_path: Path
    analysis_py_path: Path
    final_answer_md_path: Path
    verdict_json_path: Path
    report_html_path: Path
    run_log_path: Path
    data_dir: Path
    dist_dir: Path


@dataclass(frozen=True, slots=True)
class ScoreResult:
    decision: str
    justification: str
    raw_score: float
    normalized_score: float
    rubric_breakdown: list[dict[str, Any]]
    status: str
    verdict_path: Path


@dataclass(frozen=True, slots=True)
class ValidationResult:
    result: str
    reproduced_raw_score: float
    reproduced_normalized_score: float
    raw_abs_tolerance: float
    matches: bool
    review_source_path: Path
