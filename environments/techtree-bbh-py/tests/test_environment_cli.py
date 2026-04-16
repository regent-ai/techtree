import json
from pathlib import Path

from jsonschema import validate

from techtree_bbh_py.cli import main


def _schema(name: str) -> dict:
    root = Path(__file__).resolve().parents[3]
    return json.loads((root / "core" / "schemas" / name).read_text(encoding="utf-8"))


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
    assert (workspace_dir / "search.config.yaml").exists()
    assert (workspace_dir / "outputs" / "skydiscover" / "search_summary.json").exists()
    assert (workspace_dir / "outputs" / "skydiscover" / "search.log").exists()
    assert (workspace_dir / "run.source.yaml").exists()
    assert (workspace_dir / "review.source.yaml").exists()

    review_source = json.loads((workspace_dir / "review.source.yaml").read_text(encoding="utf-8"))
    validate(review_source, _schema("techtree.bbh.review-source.v1.schema.json"))
