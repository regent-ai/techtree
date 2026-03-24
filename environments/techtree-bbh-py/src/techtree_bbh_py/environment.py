from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Sequence
from uuid import uuid4

from .bundle import write_run_bundle
from .models import Capsule, MaterializedWorkspace, RunBundle
from .normalize import load_split_rows
from .workspace import materialize_workspace


def _default_workspace_root(split: str) -> Path:
    return Path.cwd() / ".techtree-bbh" / split


@dataclass(slots=True)
class BbhPyEnvironment:
    split: str
    capsules: list[Capsule]
    notebook_backend: str = "marimo-local"
    max_turns: int = 20
    results_dir: Path | None = None
    public_dataset: str | None = None
    problem_jsonl: str | None = None
    capsule_dir: Path | None = None
    official_mode: bool = False
    metadata: dict[str, str] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self.results_dir = self.results_dir.expanduser() if self.results_dir else None
        self.capsule_dir = self.capsule_dir.expanduser() if self.capsule_dir else None

    def capsule_ids(self) -> list[str]:
        return [capsule.capsule_id for capsule in self.capsules]

    def get_capsule(self, capsule_id: str) -> Capsule:
        for capsule in self.capsules:
            if capsule.capsule_id == capsule_id or capsule.task_id == capsule_id:
                return capsule
        raise KeyError(f"unknown capsule: {capsule_id}")

    def materialize(self, capsule_id: str, workspace_dir: Path | None = None) -> MaterializedWorkspace:
        capsule = self.get_capsule(capsule_id)
        workspace_root = workspace_dir or self._default_workspace_dir(capsule)
        return materialize_workspace(
            capsule,
            workspace_root,
            official_mode=self.official_mode,
            notebook_backend=self.notebook_backend,
            max_turns=self.max_turns,
        )

    def bundle(
        self,
        capsule_id: str,
        workspace_dir: Path | None = None,
        bundle_dir: Path | None = None,
        *,
        run_id: str | None = None,
    ) -> RunBundle:
        capsule = self.get_capsule(capsule_id)
        target_workspace = workspace_dir or self._default_workspace_dir(capsule)
        if self._workspace_is_complete(target_workspace):
            materialized_workspace = MaterializedWorkspace(
                capsule=capsule,
                workspace_dir=target_workspace,
                task_json_path=target_workspace / "task.json",
                protocol_md_path=target_workspace / "protocol.md",
                rubric_json_path=target_workspace / "rubric.json",
                analysis_py_path=target_workspace / "analysis.py",
                verdict_json_path=target_workspace / "verdict.json",
                data_dir=target_workspace / "data",
                artifacts_dir=target_workspace / "artifacts",
            )
        else:
            materialized_workspace = self.materialize(capsule.capsule_id, workspace_dir=target_workspace)
        target_bundle_dir = bundle_dir or self._default_bundle_dir(materialized_workspace.workspace_dir)
        return write_run_bundle(
            materialized_workspace.workspace_dir,
            target_bundle_dir,
            run_id=run_id or self._make_run_id(capsule),
            split=self.split,
            source_dataset=capsule.source_dataset,
            capsule_id=capsule.capsule_id,
        )

    def smoke(
        self,
        capsule_id: str | None = None,
        workspace_dir: Path | None = None,
        bundle_dir: Path | None = None,
    ) -> RunBundle:
        target_capsule = capsule_id or self.capsules[0].capsule_id
        return self.bundle(target_capsule, workspace_dir=workspace_dir, bundle_dir=bundle_dir)

    def _default_workspace_dir(self, capsule: Capsule) -> Path:
        base = self.capsule_dir or _default_workspace_root(self.split)
        return base / capsule.capsule_id

    def _default_bundle_dir(self, workspace_dir: Path) -> Path:
        if self.results_dir is not None:
            return self.results_dir / workspace_dir.name
        return workspace_dir.parent / f"{workspace_dir.name}-bundle"

    def _make_run_id(self, capsule: Capsule) -> str:
        return f"{self.split}-{capsule.capsule_id}-{uuid4().hex[:10]}"

    def _workspace_is_complete(self, workspace_dir: Path) -> bool:
        required = [
            workspace_dir / "task.json",
            workspace_dir / "protocol.md",
            workspace_dir / "rubric.json",
            workspace_dir / "analysis.py",
            workspace_dir / "verdict.json",
            workspace_dir / "data",
        ]
        return all(path.exists() for path in required)


def load_environment(
    *,
    split: str = "climb",
    task_ids: Sequence[str] | None = None,
    notebook_backend: str = "marimo-local",
    max_turns: int = 20,
    results_dir: str | None = None,
    public_dataset: str | None = None,
    problem_jsonl: str | None = None,
    capsule_dir: str | None = None,
    official_mode: bool = False,
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
        notebook_backend=notebook_backend,
        max_turns=max_turns,
        results_dir=Path(results_dir) if results_dir else None,
        public_dataset=public_dataset,
        problem_jsonl=problem_jsonl,
        capsule_dir=Path(capsule_dir) if capsule_dir else None,
        official_mode=official_mode,
        metadata={
            "source": public_dataset or problem_jsonl or f"techtree-bbh-py/{split}",
        },
    )
