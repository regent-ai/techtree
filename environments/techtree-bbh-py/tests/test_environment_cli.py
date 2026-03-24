import json
from pathlib import Path

from jsonschema import validate

from techtree_bbh_py.cli import main
from techtree_bbh_py.env import load_environment


def _schema(name: str) -> dict:
    root = Path(__file__).resolve().parents[3]
    return json.loads((root / "core" / "schemas" / name).read_text(encoding="utf-8"))


def test_load_environment_rejects_legacy_splits() -> None:
    try:
        load_environment(split="holdout")
    except ValueError as error:
        assert "unsupported split" in str(error)
    else:
        raise AssertionError("expected legacy split to be rejected")


def test_cli_smoke_flow_materializes_scores_and_validates(tmp_path: Path, capsys) -> None:
    workspace_dir = tmp_path / "workspace"

    exit_code = main(
        [
            "--split",
            "benchmark",
            "smoke",
            "--workspace",
            str(workspace_dir),
            "--capsule-id",
            "benchmark-001",
        ]
    )

    assert exit_code == 0
    output = json.loads(capsys.readouterr().out)
    assert output["capsule_id"] == "benchmark-001"
    assert output["validation"]["result"] == "confirmed"
    assert (workspace_dir / "run.source.yaml").exists()
    assert (workspace_dir / "review.source.yaml").exists()

    review_source = json.loads((workspace_dir / "review.source.yaml").read_text(encoding="utf-8"))
    validate(review_source, _schema("techtree.bbh.review-source.v1.schema.json"))
