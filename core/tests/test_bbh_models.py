from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from techtree_core.bbh_models import (
    BbhArtifactSourceV1,
    BbhGenomeSourceV1,
    BbhReviewSourceV1,
    BbhRunSourceV1,
)


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "fixtures" / "golden" / "bbh_sources"


def load_fixture(name: str) -> dict:
    path = FIXTURES / name
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def test_bbh_positive_validation_cases() -> None:
    climb_capsule = BbhArtifactSourceV1.model_validate(load_fixture("artifact_climb_fixed.source.yaml"))
    benchmark_capsule = BbhArtifactSourceV1.model_validate(load_fixture("artifact_benchmark_fixed.source.yaml"))
    challenge_capsule = BbhArtifactSourceV1.model_validate(load_fixture("artifact_challenge_family.source.yaml"))
    draft_capsule = BbhArtifactSourceV1.model_validate(load_fixture("artifact_draft_challenge.source.yaml"))
    published_challenge = BbhArtifactSourceV1.model_validate(
        load_fixture("artifact_published_challenge.source.yaml")
    )
    genome = BbhGenomeSourceV1.model_validate(load_fixture("genome.source.yaml"))
    climb_run = BbhRunSourceV1.model_validate(load_fixture("run_climb_fixed.source.yaml"))
    benchmark_run = BbhRunSourceV1.model_validate(load_fixture("run_benchmark_fixed.source.yaml"))
    challenge_run = BbhRunSourceV1.model_validate(load_fixture("run_challenge_family.source.yaml"))
    review = BbhReviewSourceV1.model_validate(load_fixture("review_official_replay.source.yaml"))

    assert climb_capsule.bbh.split == "climb"
    assert benchmark_capsule.bbh.split == "benchmark"
    assert challenge_capsule.bbh.split == "challenge"
    assert draft_capsule.bbh.split == "draft"
    assert published_challenge.bbh.split == "challenge"
    assert genome.model_id == "gpt-test"
    assert climb_run.bbh.split == "climb"
    assert benchmark_run.bbh.assignment_ref == "assign_benchmark_1"
    assert challenge_run.instance.family_ref == "fam_challenge_1"
    assert review.bbh.role == "official"


def test_fixed_artifact_requires_instance_ref() -> None:
    payload = load_fixture("artifact_climb_fixed.source.yaml")
    payload["bbh"]["instance_ref"] = None

    with pytest.raises(ValueError, match="instance_ref"):
        BbhArtifactSourceV1.model_validate(payload)


def test_family_artifact_requires_family_ref() -> None:
    payload = load_fixture("artifact_challenge_family.source.yaml")
    payload["bbh"]["family_ref"] = None

    with pytest.raises(ValueError, match="family_ref"):
        BbhArtifactSourceV1.model_validate(payload)


def test_climb_capsules_cannot_use_draft_only() -> None:
    payload = load_fixture("artifact_climb_fixed.source.yaml")
    payload["bbh"]["assignment_policy"] = "draft_only"

    with pytest.raises(ValueError, match="climb capsules cannot use assignment_policy=draft_only"):
        BbhArtifactSourceV1.model_validate(payload)


@pytest.mark.parametrize("fixture_name", ["artifact_benchmark_fixed.source.yaml", "artifact_published_challenge.source.yaml"])
def test_benchmark_and_challenge_capsules_cannot_use_public_next(fixture_name: str) -> None:
    payload = load_fixture(fixture_name)
    payload["bbh"]["assignment_policy"] = "public_next"

    with pytest.raises(ValueError, match="benchmark/challenge capsules cannot use assignment_policy=public_next"):
        BbhArtifactSourceV1.model_validate(payload)


def test_draft_capsules_must_use_draft_only() -> None:
    payload = load_fixture("artifact_draft_challenge.source.yaml")
    payload["bbh"]["assignment_policy"] = "operator_assigned"

    with pytest.raises(ValueError, match="draft capsules must use assignment_policy=draft_only"):
        BbhArtifactSourceV1.model_validate(payload)


@pytest.mark.parametrize("fixture_name", ["run_benchmark_fixed.source.yaml", "run_challenge_family.source.yaml"])
def test_benchmark_and_challenge_runs_require_assignment_ref(fixture_name: str) -> None:
    payload = load_fixture(fixture_name)
    payload["bbh"]["assignment_ref"] = None

    with pytest.raises(ValueError, match="assignment_ref"):
        BbhRunSourceV1.model_validate(payload)


def test_score_may_only_appear_on_completed_or_failed_runs() -> None:
    payload = load_fixture("run_climb_fixed.source.yaml")
    payload["status"] = "running"

    with pytest.raises(ValueError, match="score may only be present"):
        BbhRunSourceV1.model_validate(payload)


def test_genome_executor_id_must_match_bbh_genome_ref() -> None:
    payload = load_fixture("run_climb_fixed.source.yaml")
    payload["executor"]["id"] = "genome:beta"

    with pytest.raises(ValueError, match="must match bbh.genome_ref"):
        BbhRunSourceV1.model_validate(payload)


def test_official_validations_must_use_replay() -> None:
    payload = load_fixture("review_official_replay.source.yaml")
    payload["method"] = "manual"

    with pytest.raises(ValueError, match="must use method='replay'"):
        BbhReviewSourceV1.model_validate(payload)


def test_confirmed_replay_requires_reproduced_scores() -> None:
    payload = load_fixture("review_official_replay.source.yaml")
    payload["bbh"]["reproduced_raw_score"] = None

    with pytest.raises(ValueError, match="must include reproduced scores"):
        BbhReviewSourceV1.model_validate(payload)
