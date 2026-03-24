from __future__ import annotations

from enum import Enum
from typing import Any, Annotated, Literal
from pathlib import PurePosixPath

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator


Digest = Annotated[str, StringConstraints(pattern=r"^sha256:[0-9a-f]{64}$")]
OpaqueRef = Annotated[str, StringConstraints(min_length=1, max_length=256)]
SemVerish = Annotated[str, StringConstraints(min_length=1, max_length=64)]
RelativePath = Annotated[str, StringConstraints(min_length=1, max_length=512)]


def _ensure_relative_posix_path(value: str) -> str:
    path = PurePosixPath(value)
    if not value or value.strip() == ".":
      raise ValueError("path must not be empty")
    if path.is_absolute():
      raise ValueError("path must be relative, not absolute")
    if ".." in path.parts:
      raise ValueError("path must not contain '..'")
    if "\\" in value:
      raise ValueError("path must use POSIX separators ('/')")
    return value


class BbhBaseModel(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True, use_enum_values=True)


class Split(str, Enum):
    climb = "climb"
    benchmark = "benchmark"
    challenge = "challenge"
    draft = "draft"


class Provider(str, Enum):
    bbh = "bbh"
    bbh_train = "bbh_train"
    techtree = "techtree"


class HarnessType(str, Enum):
    openclaw = "openclaw"
    hermes = "hermes"
    claude_code = "claude_code"
    custom = "custom"


class AssignmentPolicy(str, Enum):
    public_next = "public_next"
    operator_assigned = "operator_assigned"
    validator_assigned = "validator_assigned"
    draft_only = "draft_only"


class KeepDecision(str, Enum):
    keep = "keep"
    discard = "discard"
    pending = "pending"


class RunStatus(str, Enum):
    created = "created"
    running = "running"
    completed = "completed"
    failed = "failed"


class ReviewMethod(str, Enum):
    replay = "replay"
    manual = "manual"
    replication = "replication"


class ReviewResult(str, Enum):
    confirmed = "confirmed"
    rejected = "rejected"
    mixed = "mixed"
    needs_revision = "needs_revision"


class ValidationRole(str, Enum):
    official = "official"
    community = "community"


class ParentRelation(str, Enum):
    revision = "revision"
    fork = "fork"
    derivative = "derivative"
    reference = "reference"


class SourceKind(str, Enum):
    paper = "paper"
    dataset = "dataset"
    code = "code"
    website = "website"
    artifact = "artifact"
    other = "other"


class EvidenceKind(str, Enum):
    file = "file"
    run = "run"
    note = "note"
    external = "external"


class NetworkPolicy(str, Enum):
    none = "none"
    declared = "declared"


class FilesystemPolicy(str, Enum):
    read_only = "read_only"
    workspace_write = "workspace_write"


class SecretsPolicy(str, Enum):
    forbidden = "forbidden"
    declared = "declared"


class RuntimePolicy(BbhBaseModel):
    network: NetworkPolicy = NetworkPolicy.none
    filesystem: FilesystemPolicy = FilesystemPolicy.workspace_write
    secrets: SecretsPolicy = SecretsPolicy.forbidden
    gpu: bool = False


class EnvironmentSystem(BbhBaseModel):
    python: str = "3.11"
    platform: str = "linux/amd64"


class EnvironmentSource(BbhBaseModel):
    lockfile_path: RelativePath | None = "uv.lock"
    image: str | None = None
    system: EnvironmentSystem = Field(default_factory=EnvironmentSystem)
    runtime_policy: RuntimePolicy = Field(default_factory=RuntimePolicy)

    _validate_lockfile = field_validator("lockfile_path")(_ensure_relative_posix_path)


class ParentLink(BbhBaseModel):
    artifact_id: OpaqueRef
    relation: ParentRelation
    note: str | None = None


class NotebookSource(BbhBaseModel):
    entrypoint: RelativePath = "analysis.py"
    include: list[RelativePath] = Field(
        default_factory=lambda: [
            "analysis.py",
            "protocol.md",
            "rubric.json",
            "task.json",
            "eval/**/*.py",
            "uv.lock",
            "pyproject.toml",
        ]
    )
    exclude: list[RelativePath] = Field(default_factory=lambda: ["outputs/**", "dist/**"])
    marimo_version: str | None = None

    _validate_entrypoint = field_validator("entrypoint")(_ensure_relative_posix_path)
    _validate_include = field_validator("include")(lambda xs: [_ensure_relative_posix_path(x) for x in xs])
    _validate_exclude = field_validator("exclude")(lambda xs: [_ensure_relative_posix_path(x) for x in xs])


class ProvenanceSource(BbhBaseModel):
    source_repo: str | None = None
    source_commit: str | None = None
    build_attestation_files: list[RelativePath] = Field(default_factory=list)

    _validate_attestations = field_validator("build_attestation_files")(
        lambda xs: [_ensure_relative_posix_path(x) for x in xs]
    )


class ClaimSource(BbhBaseModel):
    text: str = Field(min_length=1)


class SourceRef(BbhBaseModel):
    kind: SourceKind
    ref: str = Field(min_length=1)
    license: str | None = None
    note: str | None = None


class ArtifactLicenses(BbhBaseModel):
    notebook: str | None = None
    data: str | None = None
    outputs: str | None = None


class OutputContract(BbhBaseModel):
    required_files: list[RelativePath] = Field(default_factory=lambda: ["outputs/verdict.json"])
    required_keys: list[str] = Field(default_factory=lambda: ["decision", "justification", "metrics"])

    _validate_required_files = field_validator("required_files")(
        lambda xs: [_ensure_relative_posix_path(x) for x in xs]
    )


class ProtocolSpec(BbhBaseModel):
    entrypoint: RelativePath = "eval/run.py"
    allowed_tools: list[str] = Field(default_factory=lambda: ["python"])
    max_runtime_s: int | None = Field(default=1800, ge=1)
    max_turns: int | None = Field(default=20, ge=1)
    output_contract: OutputContract = Field(default_factory=OutputContract)

    _validate_entrypoint = field_validator("entrypoint")(_ensure_relative_posix_path)


class ScoreRange(BbhBaseModel):
    min: float = 0.0
    max: float = 10.0

    @model_validator(mode="after")
    def validate_range(self) -> "ScoreRange":
        if self.max <= self.min:
            raise ValueError("score_range.max must be greater than score_range.min")
        return self


class RubricSpec(BbhBaseModel):
    scorer: RelativePath = "eval/score.py"
    primary_metric: str = "raw_score"
    secondary_metrics: list[str] = Field(default_factory=lambda: ["normalized_score"])
    score_range: ScoreRange = Field(default_factory=ScoreRange)
    aggregation: Literal["deterministic", "mean", "custom"] = "deterministic"
    pass_rule: str = "see rubric.json"

    _validate_scorer = field_validator("scorer")(_ensure_relative_posix_path)


class FamilyGeneratorSpec(BbhBaseModel):
    entrypoint: RelativePath = "eval/generate.py"
    seed_type: Literal["uint64"] = "uint64"
    determinism: Literal["seed_only", "seed_plus_params"] = "seed_only"
    params_schema: RelativePath = "schemas/family.json"

    _validate_paths = field_validator("entrypoint", "params_schema")(_ensure_relative_posix_path)


class FixedEvalSpec(BbhBaseModel):
    mode: Literal["fixed"] = "fixed"
    protocol: ProtocolSpec = Field(default_factory=ProtocolSpec)
    rubric: RubricSpec = Field(default_factory=RubricSpec)


class FamilyEvalSpec(BbhBaseModel):
    mode: Literal["family"] = "family"
    protocol: ProtocolSpec = Field(default_factory=ProtocolSpec)
    rubric: RubricSpec = Field(default_factory=RubricSpec)
    generator: FamilyGeneratorSpec


EvalSpec = Annotated[FixedEvalSpec | FamilyEvalSpec, Field(discriminator="mode")]


class BbhDataRef(BbhBaseModel):
    path: RelativePath
    note: str | None = None
    license: str | None = None

    _validate_path = field_validator("path")(_ensure_relative_posix_path)


class BbhArtifactProfile(BbhBaseModel):
    split: Split
    language: Literal["python"] = "python"
    provider: Provider
    provider_ref: str = Field(min_length=1)
    family_ref: str | None = None
    instance_ref: str | None = None
    hypothesis: str = Field(min_length=1)
    protocol_path: RelativePath = "protocol.md"
    rubric_path: RelativePath = "rubric.json"
    data_refs: list[BbhDataRef] = Field(default_factory=list)
    assignment_policy: AssignmentPolicy
    difficulty: float | None = Field(default=None, ge=0.0)
    tags: list[str] = Field(default_factory=list)
    source_paper_ref: str | None = None

    _validate_protocol_path = field_validator("protocol_path")(_ensure_relative_posix_path)
    _validate_rubric_path = field_validator("rubric_path")(_ensure_relative_posix_path)

    @model_validator(mode="after")
    def validate_split_policy(self) -> "BbhArtifactProfile":
        if self.split == Split.climb and self.assignment_policy == AssignmentPolicy.draft_only:
            raise ValueError("climb capsules cannot use assignment_policy=draft_only")
        if self.split in {Split.benchmark, Split.challenge} and self.assignment_policy == AssignmentPolicy.public_next:
            raise ValueError("benchmark/challenge capsules cannot use assignment_policy=public_next")
        if self.split == Split.draft and self.assignment_policy != AssignmentPolicy.draft_only:
            raise ValueError("draft capsules must use assignment_policy=draft_only")
        return self


class BbhArtifactSourceV1(BbhBaseModel):
    schema_version: Literal["techtree.bbh.artifact-source.v1"] = "techtree.bbh.artifact-source.v1"
    title: str = Field(min_length=1)
    summary: str = Field(min_length=1)
    parents: list[ParentLink] = Field(default_factory=list)
    notebook: NotebookSource = Field(default_factory=NotebookSource)
    env: EnvironmentSource = Field(default_factory=EnvironmentSource)
    provenance: ProvenanceSource = Field(default_factory=ProvenanceSource)
    claims: list[ClaimSource] = Field(default_factory=list)
    notes: str | None = None
    sources: list[SourceRef] = Field(default_factory=list)
    licenses: ArtifactLicenses = Field(default_factory=ArtifactLicenses)
    eval: EvalSpec
    bbh: BbhArtifactProfile

    @model_validator(mode="after")
    def validate_eval_against_bbh(self) -> "BbhArtifactSourceV1":
        if self.eval.mode == "fixed" and not self.bbh.instance_ref:
            raise ValueError("bbh.instance_ref is required when eval.mode='fixed'")
        if self.eval.mode == "family" and not self.bbh.family_ref:
            raise ValueError("bbh.family_ref is required when eval.mode='family'")
        return self


class BbhGenomeSourceV1(BbhBaseModel):
    schema_version: Literal["techtree.bbh.genome-source.v1"] = "techtree.bbh.genome-source.v1"
    label: str | None = None
    parent_genome_ref: OpaqueRef | None = None
    model_id: str = Field(min_length=1)
    harness_type: HarnessType
    harness_version: SemVerish
    prompt_pack_version: SemVerish
    skill_pack_version: SemVerish
    tool_profile: str = Field(min_length=1)
    runtime_image: str = Field(min_length=1)
    helper_code_hash: Digest | None = None
    data_profile: str | None = None
    axes: dict[str, Any] = Field(default_factory=dict)
    notes: str | None = None


class RunExecutor(BbhBaseModel):
    type: Literal["genome", "actor", "system"]
    id: OpaqueRef | None = None
    harness: HarnessType
    harness_version: SemVerish
    profile: str | None = None

    @model_validator(mode="after")
    def validate_executor_id(self) -> "RunExecutor":
        if self.type == "genome" and not self.id:
            raise ValueError("executor.id is required when executor.type='genome'")
        return self


class RunInstance(BbhBaseModel):
    instance_ref: str = Field(min_length=1)
    family_ref: str | None = None
    seed: int | str | None = None


class RunOrigin(BbhBaseModel):
    workload: Literal["bbh"] = "bbh"
    transport: Literal["local", "xmtp", "gossipsub", "api"] = "local"
    trigger: Literal["manual", "assignment", "validator", "automation"] = "manual"


class RunPaths(BbhBaseModel):
    analysis_path: RelativePath = "analysis.py"
    verdict_path: RelativePath = "outputs/verdict.json"
    final_answer_path: RelativePath | None = "final_answer.md"
    report_path: RelativePath | None = "outputs/report.html"
    log_path: RelativePath | None = "outputs/run.log"
    genome_path: RelativePath | None = "genome.source.yaml"

    _validate_paths = field_validator(
        "analysis_path", "verdict_path", "final_answer_path", "report_path", "log_path", "genome_path"
    )(lambda v: _ensure_relative_posix_path(v) if v is not None else v)


class RunScore(BbhBaseModel):
    raw: float
    normalized: float = Field(ge=0.0, le=1.0)
    scorer_version: str | None = None


class BbhRunProfile(BbhBaseModel):
    split: Split
    genome_ref: OpaqueRef
    provider: Provider
    assignment_ref: str | None = None
    keep_decision: KeepDecision = KeepDecision.pending
    parent_genome_ref: OpaqueRef | None = None
    child_genome_ref: OpaqueRef | None = None
    notes: str | None = None

    @model_validator(mode="after")
    def validate_assignment_for_official_splits(self) -> "BbhRunProfile":
        if self.split in {Split.benchmark, Split.challenge} and not self.assignment_ref:
            raise ValueError("bbh.assignment_ref is required for benchmark/challenge runs")
        return self


class BbhRunSourceV1(BbhBaseModel):
    schema_version: Literal["techtree.bbh.run-source.v1"] = "techtree.bbh.run-source.v1"
    artifact_ref: OpaqueRef
    executor: RunExecutor
    instance: RunInstance
    origin: RunOrigin = Field(default_factory=RunOrigin)
    paths: RunPaths = Field(default_factory=RunPaths)
    status: RunStatus = RunStatus.created
    score: RunScore | None = None
    bbh: BbhRunProfile
    notes: str | None = None

    @model_validator(mode="after")
    def validate_score_against_status(self) -> "BbhRunSourceV1":
        if self.score is not None and self.status not in {RunStatus.completed, RunStatus.failed}:
            raise ValueError("score may only be present once the run has completed or failed")
        if self.executor.type == "genome" and self.executor.id != self.bbh.genome_ref:
            raise ValueError("executor.id must match bbh.genome_ref for genome-backed runs")
        return self


class ReviewTarget(BbhBaseModel):
    type: Literal["run"] = "run"
    id: OpaqueRef


class EvidenceRef(BbhBaseModel):
    kind: EvidenceKind
    ref: str = Field(min_length=1)
    hash: Digest | None = None
    note: str | None = None


class ReviewPaths(BbhBaseModel):
    replication_workspace: RelativePath | None = None
    verdict_path: RelativePath | None = None
    report_path: RelativePath | None = None
    log_path: RelativePath | None = None

    _validate_paths = field_validator(
        "replication_workspace", "verdict_path", "report_path", "log_path"
    )(lambda v: _ensure_relative_posix_path(v) if v is not None else v)


class BbhReviewProfile(BbhBaseModel):
    role: ValidationRole
    reproduced_raw_score: float | None = None
    reproduced_normalized_score: float | None = Field(default=None, ge=0.0, le=1.0)
    raw_abs_tolerance: float = Field(default=0.01, ge=0.0)
    scorer_version: str | None = None
    assignment_ref: str | None = None


class BbhReviewSourceV1(BbhBaseModel):
    schema_version: Literal["techtree.bbh.review-source.v1"] = "techtree.bbh.review-source.v1"
    target: ReviewTarget
    kind: Literal["validation"] = "validation"
    method: ReviewMethod
    result: ReviewResult
    summary: str = Field(min_length=1)
    evidence: list[EvidenceRef] = Field(default_factory=list)
    paths: ReviewPaths = Field(default_factory=ReviewPaths)
    bbh: BbhReviewProfile
    notes: str | None = None

    @model_validator(mode="after")
    def validate_review(self) -> "BbhReviewSourceV1":
        if self.bbh.role == ValidationRole.official and self.method != ReviewMethod.replay:
            raise ValueError("official BBH validations must use method='replay' in v0.1")
        if self.result == ReviewResult.confirmed and self.method == ReviewMethod.replay:
            if self.bbh.reproduced_raw_score is None or self.bbh.reproduced_normalized_score is None:
                raise ValueError("confirmed replay validations must include reproduced scores")
        return self
