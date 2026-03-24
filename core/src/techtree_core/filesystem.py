from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable


class WorkspaceError(ValueError):
    pass


def normalize_relative_path(value: str) -> str:
    path = PurePosixPath(value)
    if path.is_absolute():
        raise WorkspaceError(f"Absolute paths are not allowed: {value}")
    parts = path.parts
    if any(part == ".." for part in parts):
        raise WorkspaceError(f"Parent path traversal is not allowed: {value}")
    normalized = PurePosixPath(*parts).as_posix()
    if normalized in {"", "."}:
        raise WorkspaceError("Path cannot be empty")
    return normalized


def validate_glob_pattern(value: str) -> str:
    normalize_relative_path(value.replace("\\", "/").rstrip("/"))
    return value.replace("\\", "/")


def is_within_workspace(path: Path, workspace_root: Path) -> bool:
    resolved = path.resolve()
    root = workspace_root.resolve()
    return resolved == root or root in resolved.parents


def relative_posix_path(path: Path, workspace_root: Path) -> str:
    resolved = path.resolve()
    root = workspace_root.resolve()
    if resolved == root:
        raise WorkspaceError("Workspace root is not a file")
    if root not in resolved.parents:
        raise WorkspaceError(f"Path escapes workspace: {path}")
    return resolved.relative_to(root).as_posix()


@dataclass(frozen=True)
class DiscoveredFile:
    path: Path
    relpath: str


def expand_globs(workspace_root: Path, includes: Iterable[str], excludes: Iterable[str]) -> list[DiscoveredFile]:
    root = workspace_root.resolve()
    include_hits: dict[str, Path] = {}
    exclude_hits: set[str] = set()

    for pattern in excludes:
        pattern = validate_glob_pattern(pattern)
        for match in root.glob(pattern):
            if match.is_file():
                exclude_hits.add(relative_posix_path(match, root))

    for pattern in includes:
        pattern = validate_glob_pattern(pattern)
        for match in root.glob(pattern):
            if not match.is_file():
                continue
            relpath = relative_posix_path(match, root)
            if relpath in exclude_hits:
                continue
            include_hits.setdefault(relpath, match)

    discovered = [DiscoveredFile(path=include_hits[key], relpath=key) for key in sorted(include_hits)]
    return discovered
