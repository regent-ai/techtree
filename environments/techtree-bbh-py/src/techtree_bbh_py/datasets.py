from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable

from .models import Capsule, DataFile, RubricItem


def _as_text(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        stripped = value.strip()
        return stripped if stripped else None
    if isinstance(value, (int, float, bool)):
        return str(value)
    return None


_SUPPORTED_SPLITS = {"climb", "benchmark", "challenge", "draft"}


def _normalize_split(value: str | None) -> str:
    if value in _SUPPORTED_SPLITS:
        return value
    raise ValueError(f"unsupported split: {value}")


def _assignment_policy(split: str, raw: dict[str, Any]) -> str:
    configured = _as_text(raw.get("assignment_policy"))
    if configured:
        return configured
    if split == "draft":
        return "operator"
    return "auto_or_select"


def _provider(split: str, source_dataset: str, raw: dict[str, Any]) -> str:
    explicit = _as_text(raw.get("provider"))
    if explicit:
        return explicit
    lowered = source_dataset.lower()
    if split == "climb" or "climb" in lowered or "train" in lowered:
        return "bbh_train"
    if split == "benchmark":
        return "bbh"
    return "techtree"


def _is_python_row(raw: dict[str, Any]) -> bool:
    candidates = [
        raw.get("language"),
        raw.get("programming_language"),
        raw.get("code_language"),
        raw.get("notebook_language"),
    ]
    normalized = {candidate.strip().lower() for candidate in candidates if isinstance(candidate, str)}
    if "python" in normalized:
        return True
    return not normalized


def _protocol_lines(raw: dict[str, Any]) -> tuple[str, ...]:
    protocol = raw.get("protocol") or raw.get("protocol_steps") or raw.get("instructions")
    if isinstance(protocol, str):
        return tuple(line.strip() for line in protocol.splitlines() if line.strip())
    if isinstance(protocol, list):
        return tuple(text for entry in protocol if (text := _as_text(entry)))
    return tuple()


def _rubric_items(raw: dict[str, Any]) -> tuple[RubricItem, ...]:
    rubric = raw.get("rubric") or raw.get("rubric_items") or []
    items: list[RubricItem] = []
    for index, item in enumerate(rubric, start=1):
        if isinstance(item, str):
            items.append(RubricItem(rubric_item_id=f"rubric-{index}", description=item, points_possible=1))
            continue
        if not isinstance(item, dict):
            continue
        items.append(
            RubricItem(
                rubric_item_id=_as_text(item.get("rubric_item_id") or item.get("id")) or f"rubric-{index}",
                description=_as_text(item.get("description") or item.get("text")) or f"rubric-{index}",
                points_possible=int(item.get("points_possible") or item.get("points") or 1),
                expected_output=_as_text(item.get("expected_output") or item.get("expected")),
            )
        )
    return tuple(items)


def _data_files(raw: dict[str, Any]) -> tuple[DataFile, ...]:
    entries = raw.get("data_files") or raw.get("files") or raw.get("artifacts") or []
    if isinstance(entries, dict):
        entries = [{"name": name, "content": content} for name, content in entries.items()]
    files: list[DataFile] = []
    for index, entry in enumerate(entries, start=1):
        if isinstance(entry, str):
            files.append(DataFile(name=f"data-{index}.txt", content=entry))
            continue
        if isinstance(entry, dict):
            name = _as_text(entry.get("name") or entry.get("filename") or entry.get("path"))
            content = entry.get("content")
            if name and isinstance(content, str):
                files.append(DataFile(name=name, content=content))
    return tuple(files)


def normalize_capsule_row(raw: dict[str, Any], *, split: str, source_dataset: str) -> Capsule | None:
    if not _is_python_row(raw):
        return None

    normalized_split = _normalize_split(split)
    raw_split = _as_text(raw.get("split"))
    if raw_split and raw_split != normalized_split:
        if normalized_split == "climb" and raw_split == "train":
            raw_split = normalized_split
        else:
            raise ValueError(f"unsupported split: {raw_split}")

    capsule_id = _as_text(raw.get("capsule_id") or raw.get("task_id") or raw.get("id"))
    if not capsule_id:
        return None

    family_ref = _as_text(raw.get("family_ref") or raw.get("family_id"))
    instance_ref = _as_text(raw.get("instance_ref") or raw.get("instance_id")) or capsule_id
    mode = _as_text(raw.get("mode")) or ("family" if family_ref else "fixed")

    return Capsule(
        capsule_id=capsule_id,
        split=normalized_split,  # type: ignore[arg-type]
        language="python",
        mode=mode,  # type: ignore[arg-type]
        provider=_provider(normalized_split, source_dataset, raw),  # type: ignore[arg-type]
        provider_ref=_as_text(raw.get("provider_ref")) or capsule_id,
        family_ref=family_ref,
        instance_ref=instance_ref if mode == "fixed" else None,
        assignment_policy=_assignment_policy(normalized_split, raw),  # type: ignore[arg-type]
        title=_as_text(raw.get("title") or raw.get("name")) or capsule_id,
        hypothesis=_as_text(raw.get("hypothesis") or raw.get("question") or raw.get("prompt")) or "",
        protocol=_protocol_lines(raw),
        rubric=_rubric_items(raw),
        data_files=_data_files(raw),
        raw=dict(raw),
    )


def load_jsonl_rows(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def _candidate_input_paths(split: str, public_dataset: str | None, problem_jsonl: str | None) -> list[Path]:
    candidates: list[Path] = []
    if problem_jsonl:
        candidates.append(Path(problem_jsonl).expanduser())
    if public_dataset:
        candidates.append(Path(public_dataset).expanduser())
    fixture_name = {
        "climb": "climb_py_public.jsonl",
        "benchmark": "benchmark_py_public.jsonl",
        "challenge": "challenge_py_public.jsonl",
        "draft": "draft_py_private.jsonl",
    }[split]
    candidates.append(Path(__file__).resolve().parent / "splits" / fixture_name)
    return candidates


def load_split_rows(
    split: str,
    *,
    task_ids: Iterable[str] | None = None,
    public_dataset: str | None = None,
    problem_jsonl: str | None = None,
    rows: Iterable[dict[str, Any]] | None = None,
) -> list[Capsule]:
    normalized_split = _normalize_split(split)
    source_dataset = public_dataset or problem_jsonl or f"techtree-bbh-py/{normalized_split}"
    selected_ids = set(task_ids or [])

    if rows is not None:
        raw_rows = list(rows)
    else:
        raw_rows = []
        for candidate in _candidate_input_paths(normalized_split, public_dataset, problem_jsonl):
            if candidate.exists():
                raw_rows = load_jsonl_rows(candidate)
                break

    capsules = [
        capsule
        for capsule in (
            normalize_capsule_row(row, split=normalized_split, source_dataset=source_dataset) for row in raw_rows
        )
        if capsule is not None
    ]
    capsules = sorted(capsules, key=lambda capsule: capsule.capsule_id)
    if selected_ids:
        capsules = [capsule for capsule in capsules if capsule.capsule_id in selected_ids]
    return capsules
