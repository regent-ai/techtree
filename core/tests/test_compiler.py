from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from techtree_core.cli import main
from techtree_core.compiler import compile_workspace, verify_workspace, write_compilation
from techtree_core.filesystem import WorkspaceError
from techtree_core.models import ZERO_ADDRESS
from techtree_core.schema_export import export_all_schemas


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "fixtures" / "golden"
SCHEMA_DIR = ROOT / "schemas"


def fixture_workspace(name: str) -> Path:
    return FIXTURES / name


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


@pytest.mark.parametrize(
    "name,node_type",
    [
        ("artifact_plain", "artifact"),
        ("artifact_derivative", "artifact"),
        ("artifact_fixed", "artifact"),
        ("artifact_family", "artifact"),
        ("run_no_score", "run"),
        ("run_scored", "run"),
        ("review_challenge", "review"),
        ("review_validation", "review"),
    ],
)
def test_compile_matches_golden_fixtures(tmp_path: Path, name: str, node_type: str) -> None:
    workspace = fixture_workspace(name)
    result = compile_workspace(workspace, author=ZERO_ADDRESS)
    assert result.node_type == node_type
    output_dir = tmp_path / name / "dist"
    write_compilation(result, output_dir=output_dir)

    expected_dist = workspace / "dist"
    assert expected_dist.exists()
    assert (output_dir / "payload.index.json").read_text(encoding="utf-8") == (
        expected_dist / "payload.index.json"
    ).read_text(encoding="utf-8")
    assert (output_dir / f"{node_type}.manifest.json").read_text(encoding="utf-8") == (
        expected_dist / f"{node_type}.manifest.json"
    ).read_text(encoding="utf-8")
    assert (output_dir / "node-header.json").read_text(encoding="utf-8") == (
        expected_dist / "node-header.json"
    ).read_text(encoding="utf-8")
    assert (output_dir / "checksums.txt").read_text(encoding="utf-8") == (
        expected_dist / "checksums.txt"
    ).read_text(encoding="utf-8")


@pytest.mark.parametrize(
    "name",
    [
        "artifact_plain",
        "artifact_derivative",
        "artifact_fixed",
        "artifact_family",
        "run_no_score",
        "run_scored",
        "review_challenge",
        "review_validation",
    ],
)
def test_hashes_are_stable_across_runs(name: str) -> None:
    workspace = fixture_workspace(name)
    first = compile_workspace(workspace)
    second = compile_workspace(workspace)
    assert first.node_id == second.node_id
    assert first.payload_hash == second.payload_hash
    assert first.header.model_dump(exclude_none=True) == second.header.model_dump(exclude_none=True)


def test_verify_workspace_matches_golden_outputs() -> None:
    result = verify_workspace(fixture_workspace("artifact_family"))
    assert result.ok is True
    assert result.node_id == result.expected_node_id


def test_run_compile_includes_harness_and_origin_metadata(tmp_path: Path) -> None:
    workspace = tmp_path / "run_with_origin"
    shutil.copytree(fixture_workspace("run_scored"), workspace)
    source_path = workspace / "run.source.yaml"
    source_path.write_text(
        source_path.read_text(encoding="utf-8").replace(
            "  version_ref: \"git:example/genomes#2222222\"\n\ninstance:\n",
            "  version_ref: \"git:example/genomes#2222222\"\n  harness:\n    kind: hermes\n    profile: bbh\n    entrypoint: null\n\norigin:\n  kind: xmtp_group\n  transport: xmtp\n  session_id: \"session-bbh-1\"\n  trigger_ref: \"xmtp:group:bbh\"\n\ninstance:\n",
        ),
        encoding="utf-8",
    )

    result = compile_workspace(workspace, author=ZERO_ADDRESS)
    manifest = result.manifest.model_dump(exclude_none=True, mode="json")

    assert manifest["executor"]["harness"] == {
        "kind": "hermes",
        "profile": "bbh",
    }
    assert manifest["origin"] == {
        "kind": "xmtp_group",
        "transport": "xmtp",
        "session_id": "session-bbh-1",
        "trigger_ref": "xmtp:group:bbh",
    }


def test_schema_export_matches_checked_in_files(tmp_path: Path) -> None:
    exported = export_all_schemas(tmp_path)
    assert SCHEMA_DIR.exists()
    for filename, path in exported.items():
        checked_in = SCHEMA_DIR / filename
        assert checked_in.exists()
        assert path.read_text(encoding="utf-8") == checked_in.read_text(encoding="utf-8")


def test_symlink_escape_is_rejected(tmp_path: Path) -> None:
    outside = tmp_path / "outside.txt"
    outside.write_text("secret", encoding="utf-8")
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    (workspace / "notebooks").mkdir()
    source = workspace / "artifact.source.yaml"
    source.write_text(
        """
schema_version: techtree.artifact-source.v1
title: "Symlink test"
summary: "Rejects escaping symlinks"
notebook:
  entrypoint: notebooks/main.py
  include:
    - notebooks/**/*.py
    - linked.txt
  exclude: []
  marimo_version: "0.11.8"
env:
  lockfile_path: linked.txt
  image: null
  system:
    python: "3.11"
    platform: "linux/amd64"
  runtime_policy:
    network: none
    filesystem: workspace_write
    secrets: forbidden
    gpu: false
  external_resources: []
""".strip()
        + "\n",
        encoding="utf-8",
    )
    (workspace / "notebooks" / "main.py").write_text("print('ok')\n", encoding="utf-8")
    (workspace / "linked.txt").symlink_to(outside)

    with pytest.raises(WorkspaceError):
        compile_workspace(workspace)


def test_cli_compile_smoke(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    workspace = fixture_workspace("run_scored")
    exit_code = main(["--author", ZERO_ADDRESS, "compile", str(workspace), "--output-dir", str(tmp_path / "dist")])
    assert exit_code == 0
    out = capsys.readouterr().out
    assert '"node_id"' in out
