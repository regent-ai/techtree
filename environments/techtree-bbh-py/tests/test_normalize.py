import json
from pathlib import Path

from techtree_bbh_py.datasets import load_split_rows, normalize_capsule_row


def test_normalize_filters_non_python_rows() -> None:
    raw = {
        "capsule_id": "capsule-r",
        "language": "r",
        "title": "Ignore me",
        "hypothesis": "This should be ignored.",
    }

    assert normalize_capsule_row(raw, split="climb", source_dataset="fixture") is None


def test_load_split_rows_hard_cuts_climb_fixture_names() -> None:
    capsules = load_split_rows("climb")

    assert [capsule.capsule_id for capsule in capsules] == ["climb-001"]
    assert capsules[0].split == "climb"
    assert capsules[0].assignment_policy == "public_next"


def test_load_split_rows_supports_public_challenge_family_capsules() -> None:
    capsules = load_split_rows("challenge")

    assert [capsule.capsule_id for capsule in capsules] == [
        "challenge-001",
        "challenge-family-001",
    ]
    assert capsules[1].mode == "family"
    assert capsules[1].family_ref == "family-challenge-001"
    assert capsules[1].assignment_policy == "validator_assigned"


def test_load_split_rows_supports_family_capsules_for_draft() -> None:
    capsules = load_split_rows("draft")

    assert [capsule.capsule_id for capsule in capsules] == ["draft-family-001"]
    assert capsules[0].mode == "family"
    assert capsules[0].family_ref == "family-draft-001"
    assert capsules[0].instance_ref is None


def test_problem_jsonl_input_overrides_fixture_lookup(tmp_path: Path) -> None:
    custom_path = tmp_path / "custom.jsonl"
    custom_path.write_text(
        json.dumps(
            {
                "capsule_id": "custom-001",
                "split": "climb",
                "language": "python",
                "title": "Custom capsule",
                "hypothesis": "A custom row is loaded.",
                "protocol": ["Open the data", "Write the answer"],
                "rubric": [{"rubric_item_id": "final_objective", "description": "Decide", "points_possible": 5}],
            }
        )
        + "\n",
        encoding="utf-8",
    )

    capsules = load_split_rows("climb", problem_jsonl=str(custom_path))

    assert [capsule.capsule_id for capsule in capsules] == ["custom-001"]
