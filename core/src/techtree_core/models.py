from __future__ import annotations

from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from .filesystem import WorkspaceError, normalize_relative_path, validate_glob_pattern

ZERO_ADDRESS = "0x" + "0" * 40
ZERO_BYTES32 = "0x" + "0" * 64


def _validate_bytes32(value: str) -> str:
    if not isinstance(value, str):
        raise TypeError("Expected hex string")
    if not value.startswith("0x") or len(value) != 66:
        raise ValueError("Expected 0x-prefixed bytes32 hex")
    body = value[2:]
    if body != body.lower():
        raise ValueError("bytes32 hex must be lowercase")
    int(body, 16)
    return value


def _validate_address(value: str) -> str:
    if not isinstance(value, str):
        raise TypeError("Expected hex string")
    if not value.startswith("0x") or len(value) != 42:
        raise ValueError("Expected 0x-prefixed address hex")
    body = value[2:]
    if body != body.lower():
        raise ValueError("Address hex must be lowercase")
    int(body, 16)
    return value


class HexBytes32(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    value: str

    @field_validator("value")
    @classmethod
    def _check_value(cls, value: str) -> str:
        return _validate_bytes32(value)


class SourceBaseModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CanonicalBaseModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class ParentLink(SourceBaseModel):
    artifact_id: str
    relation: Literal["revision", "fork", "derivative", "reference"]
    note: str | None = None

    _artifact_id = field_validator("artifact_id")(_validate_bytes32)


class NotebookSource(SourceBaseModel):
    entrypoint: str
    include: list[str] = Field(default_factory=list)
    exclude: list[str] = Field(default_factory=list)
    marimo_version: str

    @field_validator("entrypoint")
    @classmethod
    def _entrypoint(cls, value: str) -> str:
        return normalize_relative_path(value)

    @field_validator("include", "exclude")
    @classmethod
    def _patterns(cls, values: list[str]) -> list[str]:
        if not values:
            return values
        return [validate_glob_pattern(value) for value in values]

    @model_validator(mode="after")
    def _check_include(self) -> "NotebookSource":
        if not self.include:
            raise ValueError("notebook.include must contain at least one pattern")
        return self


class SystemSpec(SourceBaseModel):
    python: str
    platform: str


class RuntimePolicy(SourceBaseModel):
    network: Literal["none", "declared"]
    filesystem: Literal["read_only", "workspace_write"]
    secrets: Literal["forbidden", "declared"]
    gpu: bool


class ExternalResource(SourceBaseModel):
    kind: str
    ref: str
    license: str | None = None
    note: str | None = None


class EnvSource(SourceBaseModel):
    lockfile_path: str
    image: str | None = None
    system: SystemSpec
    runtime_policy: RuntimePolicy
    external_resources: list[ExternalResource] = Field(default_factory=list)

    @field_validator("lockfile_path")
    @classmethod
    def _lockfile_path(cls, value: str) -> str:
        return normalize_relative_path(value)


class ProvenanceSource(SourceBaseModel):
    source_repo: str
    source_commit: str
    build_attestation_files: list[str] = Field(default_factory=list)

    @field_validator("build_attestation_files")
    @classmethod
    def _attestations(cls, values: list[str]) -> list[str]:
        return [normalize_relative_path(value) for value in values]


class Claim(SourceBaseModel):
    text: str


class SourceCitation(SourceBaseModel):
    kind: Literal["paper", "dataset", "code", "website", "artifact", "other"]
    ref: str
    license: str | None = None
    note: str | None = None


class ArtifactLicenses(SourceBaseModel):
    notebook: str
    data: str
    outputs: str


class EvalOutputContract(SourceBaseModel):
    required_files: list[str] = Field(default_factory=list)
    required_keys: list[str] = Field(default_factory=list)


class EvalProtocol(SourceBaseModel):
    entrypoint: str
    allowed_tools: list[str] = Field(default_factory=list)
    max_runtime_s: int | None = None
    max_tokens: int | None = None
    output_contract: EvalOutputContract

    @field_validator("entrypoint")
    @classmethod
    def _entrypoint(cls, value: str) -> str:
        return normalize_relative_path(value)


class EvalScoreRange(SourceBaseModel):
    min: float
    max: float


class EvalRubric(SourceBaseModel):
    scorer: str
    primary_metric: str
    secondary_metrics: list[str] = Field(default_factory=list)
    score_range: EvalScoreRange
    aggregation: Literal["deterministic", "mean", "custom"]
    pass_rule: str

    @field_validator("scorer")
    @classmethod
    def _scorer(cls, value: str) -> str:
        return normalize_relative_path(value)


class EvalGenerator(SourceBaseModel):
    entrypoint: str
    seed_type: Literal["uint64"]
    determinism: Literal["seed_only", "seed_plus_params"]
    params_schema: str

    @field_validator("entrypoint", "params_schema")
    @classmethod
    def _paths(cls, value: str) -> str:
        return normalize_relative_path(value)


class EvalInstance(SourceBaseModel):
    seed: int | None = None
    instance_id: str | None = None
    params: dict[str, Any] = Field(default_factory=dict)


class ArtifactEvalSource(SourceBaseModel):
    mode: Literal["fixed", "family"]
    protocol: EvalProtocol
    rubric: EvalRubric | None = None
    generator: EvalGenerator | None = None
    hidden_eval_commitment: str | None = None
    instance: EvalInstance | dict[str, Any] | None = None

    @model_validator(mode="after")
    def _check_mode(self) -> "ArtifactEvalSource":
        if self.mode == "fixed":
            if self.instance is None:
                raise ValueError("Fixed eval artifacts require instance")
            if self.generator is not None:
                raise ValueError("Fixed eval artifacts forbid generator")
        if self.mode == "family":
            if self.generator is None:
                raise ValueError("Family eval artifacts require generator")
            if self.instance is not None:
                raise ValueError("Family eval artifacts forbid instance")
        return self


class ArtifactSourceV1(SourceBaseModel):
    schema_version: Literal["techtree.artifact-source.v1"]
    title: str
    summary: str
    parents: list[ParentLink] = Field(default_factory=list)
    notebook: NotebookSource
    env: EnvSource
    provenance: ProvenanceSource | None = None
    claims: list[Claim] = Field(default_factory=list)
    notes: str | None = None
    sources: list[SourceCitation] = Field(default_factory=list)
    licenses: ArtifactLicenses | None = None
    eval: ArtifactEvalSource | None = None


class RunExecutor(SourceBaseModel):
    type: Literal["genome", "actor", "system"]
    id: str
    version_ref: str | None = None
    harness: "RunHarnessRef | None" = None


class RunHarnessRef(SourceBaseModel):
    kind: Literal["openclaw", "hermes", "claude_code", "custom"]
    profile: str
    entrypoint: str | None = None


class RunOrigin(SourceBaseModel):
    kind: Literal["local", "xmtp_dm", "xmtp_group", "gossipsub", "api", "watched_node", "scheduled", "other"]
    transport: Literal["xmtp", "gossipsub", "api", "other"] | None = None
    session_id: str | None = None
    trigger_ref: str | None = None


class RunInstance(SourceBaseModel):
    seed: int | None = None
    instance_id: str | None = None
    params: dict[str, Any] = Field(default_factory=dict)


class RunExecution(SourceBaseModel):
    output_dir: str
    allow_resume: bool = False

    @field_validator("output_dir")
    @classmethod
    def _output_dir(cls, value: str) -> str:
        return normalize_relative_path(value)


class RunSourceV1(SourceBaseModel):
    schema_version: Literal["techtree.run-source.v1"]
    artifact_id: str
    executor: RunExecutor
    origin: RunOrigin | None = None
    instance: RunInstance = Field(default_factory=RunInstance)
    execution: RunExecution

    _artifact_id = field_validator("artifact_id")(_validate_bytes32)


class ReviewTarget(SourceBaseModel):
    type: Literal["artifact", "run"]
    id: str

    _id = field_validator("id")(_validate_bytes32)


class ReviewFinding(SourceBaseModel):
    code: str
    severity: Literal["info", "warning", "error"]
    message: str


class ReviewScope(SourceBaseModel):
    level: Literal["whole", "claim", "eval", "output", "provenance", "license", "section"]
    path: str | None = None

    @field_validator("path")
    @classmethod
    def _path(cls, value: str | None) -> str | None:
        if value is None:
            return value
        return normalize_relative_path(value)


class ReviewEvidenceRef(SourceBaseModel):
    kind: Literal["artifact", "run", "review"]
    ref: str
    note: str | None = None

    _ref = field_validator("ref")(_validate_bytes32)


class ReviewAttachments(SourceBaseModel):
    include: list[str] = Field(default_factory=list)
    exclude: list[str] = Field(default_factory=list)

    @field_validator("include", "exclude")
    @classmethod
    def _patterns(cls, values: list[str]) -> list[str]:
        return [validate_glob_pattern(value) for value in values]


class ReviewEvidence(SourceBaseModel):
    refs: list[ReviewEvidenceRef] = Field(default_factory=list)
    attachments: ReviewAttachments = Field(default_factory=ReviewAttachments)


class ReviewSourceV1(SourceBaseModel):
    schema_version: Literal["techtree.review-source.v1"]
    target: ReviewTarget
    kind: Literal["validation", "challenge"]
    method: Literal["replay", "replication", "manual", "provenance", "lineage", "license", "policy", "other"]
    scope: ReviewScope
    result: Literal["confirmed", "rejected", "mixed", "needs_revision"]
    summary: str
    findings: list[ReviewFinding] = Field(default_factory=list)
    evidence: ReviewEvidence = Field(default_factory=ReviewEvidence)


class PayloadFileEntry(CanonicalBaseModel):
    path: str
    sha256: str
    size: int
    media_type: str
    role: str

    @field_validator("path")
    @classmethod
    def _path(cls, value: str) -> str:
        return normalize_relative_path(value)


class ExternalBlobEntry(CanonicalBaseModel):
    ref: str
    sha256: str
    size: int
    media_type: str
    role: str | None = None


class PayloadIndexV1(CanonicalBaseModel):
    schema_version: Literal["techtree.payload-index.v1"]
    node_type: Literal["artifact", "run", "review"]
    files: list[PayloadFileEntry]
    external_blobs: list[ExternalBlobEntry] = Field(default_factory=list)


class NotebookFileEntry(CanonicalBaseModel):
    path: str
    sha256: str
    size: int
    media_type: str
    role: str

    @field_validator("path")
    @classmethod
    def _path(cls, value: str) -> str:
        return normalize_relative_path(value)


class ArtifactNotebookSection(CanonicalBaseModel):
    entrypoint: str
    marimo_version: str
    files: list[NotebookFileEntry] = Field(default_factory=list)


class ArtifactEnvCanonical(CanonicalBaseModel):
    lockfile_path: str
    image: str | None = None
    system: SystemSpec
    runtime_policy: RuntimePolicy
    external_resources: list[ExternalResource] = Field(default_factory=list)

    @field_validator("lockfile_path")
    @classmethod
    def _lockfile_path(cls, value: str) -> str:
        return normalize_relative_path(value)


class ProvenanceCanonical(CanonicalBaseModel):
    source_repo: str
    source_commit: str
    build_attestation_files: list[str] = Field(default_factory=list)

    @field_validator("build_attestation_files")
    @classmethod
    def _attestations(cls, values: list[str]) -> list[str]:
        return [normalize_relative_path(value) for value in values]


class ArtifactManifestV1(CanonicalBaseModel):
    schema_version: Literal["techtree.artifact-manifest.v1"]
    kind: Literal["notebook", "capsule"]
    title: str
    summary: str
    parents: list[ParentLink] = Field(default_factory=list)
    notebook: ArtifactNotebookSection
    env: ArtifactEnvCanonical
    provenance: ProvenanceCanonical | None = None
    claims: list[Claim] = Field(default_factory=list)
    notes: str | None = None
    sources: list[SourceCitation] = Field(default_factory=list)
    licenses: ArtifactLicenses | None = None
    eval: ArtifactEvalSource | None = None
    payload_hash: str


class RunEnvObserved(CanonicalBaseModel):
    image: str | None = None
    python: str | None = None
    platform: str | None = None


class RunOutputFile(CanonicalBaseModel):
    path: str
    sha256: str
    size: int
    media_type: str
    role: str

    @field_validator("path")
    @classmethod
    def _path(cls, value: str) -> str:
        return normalize_relative_path(value)


class RunOutputs(CanonicalBaseModel):
    files: list[RunOutputFile] = Field(default_factory=list)
    primary_output: str | None = None
    verdict_ref: str | None = None
    log_ref: str | None = None


class RunMetrics(CanonicalBaseModel):
    score: float | None = None
    values: dict[str, Any] = Field(default_factory=dict)


class RunProvenance(CanonicalBaseModel):
    runner_id: str | None = None
    attestation_files: list[str] = Field(default_factory=list)

    @field_validator("attestation_files")
    @classmethod
    def _attestations(cls, values: list[str]) -> list[str]:
        return [normalize_relative_path(value) for value in values]


class RunManifestV1(CanonicalBaseModel):
    schema_version: Literal["techtree.run-manifest.v1"]
    artifact_id: str
    executor: RunExecutor
    origin: RunOrigin | None = None
    instance: RunInstance = Field(default_factory=RunInstance)
    status: Literal["planned", "running", "completed", "failed"]
    env_observed: RunEnvObserved | None = None
    outputs: RunOutputs | None = None
    metrics: RunMetrics | None = None
    run_provenance: RunProvenance | None = None
    payload_hash: str

    _artifact_id = field_validator("artifact_id")(_validate_bytes32)


class ReviewAttachment(CanonicalBaseModel):
    path: str
    sha256: str
    size: int
    media_type: str
    role: str

    @field_validator("path")
    @classmethod
    def _path(cls, value: str) -> str:
        return normalize_relative_path(value)


class ReviewEvidenceCanonical(CanonicalBaseModel):
    refs: list[ReviewEvidenceRef] = Field(default_factory=list)
    attachments: list[ReviewAttachment] = Field(default_factory=list)


class ReviewProvenance(CanonicalBaseModel):
    reviewer_id: str | None = None
    attestation_files: list[str] = Field(default_factory=list)

    @field_validator("attestation_files")
    @classmethod
    def _attestations(cls, values: list[str]) -> list[str]:
        return [normalize_relative_path(value) for value in values]


class ReviewManifestV1(CanonicalBaseModel):
    schema_version: Literal["techtree.review-manifest.v1"]
    target: ReviewTarget
    kind: Literal["validation", "challenge"]
    method: Literal["replay", "replication", "manual", "provenance", "lineage", "license", "policy", "other"]
    scope: ReviewScope
    result: Literal["confirmed", "rejected", "mixed", "needs_revision"]
    summary: str
    findings: list[ReviewFinding] = Field(default_factory=list)
    evidence: ReviewEvidenceCanonical
    review_provenance: ReviewProvenance | None = None
    payload_hash: str


class NodeHeaderV1(CanonicalBaseModel):
    id: str
    subject_id: str
    aux_id: str
    payload_hash: str
    node_type: int
    schema_version: int
    flags: int
    author: str

    _id = field_validator("id", "subject_id", "aux_id")(_validate_bytes32)

    @field_validator("payload_hash")
    @classmethod
    def _payload_hash(cls, value: str) -> str:
        if not value.startswith("sha256:") or len(value) != 71:
            raise ValueError("Expected sha256:<64hex> payload hash")
        int(value.split(":", 1)[1], 16)
        return value

    _author = field_validator("author")(_validate_address)


class CompilationResult(CanonicalBaseModel):
    node_type: Literal["artifact", "run", "review"]
    source_path: str
    workspace_root: str
    payload_index: PayloadIndexV1
    manifest: ArtifactManifestV1 | RunManifestV1 | ReviewManifestV1
    header: NodeHeaderV1
    node_id: str
    payload_hash: str
    manifest_hash: str
    dist_dir: str
    checksum_lines: list[str] = Field(default_factory=list)

    _node_id = field_validator("node_id", "manifest_hash")(_validate_bytes32)


class VerificationResult(CanonicalBaseModel):
    ok: bool
    node_type: str
    node_id: str
    expected_node_id: str
    payload_hash_match: bool
    header_match: bool
    manifest_match: bool
    messages: list[str] = Field(default_factory=list)
