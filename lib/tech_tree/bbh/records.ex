defmodule TechTree.BBH.Capsule do
  @moduledoc false
  use TechTree.Schema

  @workflow_states [:authoring, :review_ready, :in_review, :approved, :rejected]
  @certificate_statuses [:none, :active]

  @primary_key {:capsule_id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "bbh_capsules" do
    field :provider, :string
    field :provider_ref, :string
    field :family_ref, :string
    field :instance_ref, :string
    field :split, :string
    field :language, :string
    field :mode, :string
    field :assignment_policy, :string
    field :title, :string
    field :hypothesis, :string
    field :protocol_md, :string
    field :rubric_json, :map, default: %{}
    field :task_json, :map, default: %{}
    field :data_files, {:array, :map}, default: []
    field :artifact_source, :map, default: %{}
    field :owner_wallet_address, :string
    field :source_node_id, :integer
    field :seed, :string
    field :parent_id, :integer
    field :workflow_state, Ecto.Enum, values: @workflow_states, default: :authoring
    field :notebook_py, :string
    field :capsule_source, :map, default: %{}
    field :recommended_genome_source, :map, default: %{}
    field :genome_notes_md, :string
    field :publication_artifact_id, :string
    field :publication_review_id, :string
    field :published_at, :utc_datetime_usec
    field :certificate_status, Ecto.Enum, values: @certificate_statuses, default: :none
    field :certificate_review_id, :string
    field :certificate_scope, :string
    field :certificate_expires_at, :utc_datetime_usec

    has_many :assignments, TechTree.BBH.Assignment,
      foreign_key: :capsule_id,
      references: :capsule_id

    has_many :runs, TechTree.BBH.Run, foreign_key: :capsule_id, references: :capsule_id

    has_many :draft_proposals, TechTree.BBH.DraftProposal,
      foreign_key: :capsule_id,
      references: :capsule_id

    has_many :review_requests, TechTree.BBH.ReviewRequest,
      foreign_key: :capsule_id,
      references: :capsule_id

    has_many :review_submissions, TechTree.BBH.ReviewSubmission,
      foreign_key: :capsule_id,
      references: :capsule_id

    timestamps()
  end

  def changeset(capsule, attrs) do
    capsule
    |> cast(attrs, [
      :capsule_id,
      :provider,
      :provider_ref,
      :family_ref,
      :instance_ref,
      :split,
      :language,
      :mode,
      :assignment_policy,
      :title,
      :hypothesis,
      :protocol_md,
      :rubric_json,
      :task_json,
      :data_files,
      :artifact_source,
      :owner_wallet_address,
      :source_node_id,
      :seed,
      :parent_id,
      :workflow_state,
      :notebook_py,
      :capsule_source,
      :recommended_genome_source,
      :genome_notes_md,
      :publication_artifact_id,
      :publication_review_id,
      :published_at,
      :certificate_status,
      :certificate_review_id,
      :certificate_scope,
      :certificate_expires_at
    ])
    |> validate_required([
      :capsule_id,
      :provider,
      :provider_ref,
      :split,
      :language,
      :mode,
      :assignment_policy,
      :title,
      :hypothesis,
      :protocol_md,
      :rubric_json,
      :task_json
    ])
    |> check_constraint(:workflow_state, name: :bbh_capsules_workflow_state_check)
    |> check_constraint(:certificate_status, name: :bbh_capsules_certificate_status_check)
  end
end

defmodule TechTree.BBH.Assignment do
  @moduledoc false
  use TechTree.Schema

  @statuses [:assigned, :completed]

  @primary_key {:assignment_ref, :string, autogenerate: false}
  @foreign_key_type :string

  schema "bbh_assignments" do
    field :capsule_id, :string
    field :split, :string
    field :status, Ecto.Enum, values: @statuses
    field :agent_wallet_address, :string
    field :agent_token_id, :string
    field :origin, :string
    field :completed_at, :utc_datetime_usec

    belongs_to :capsule, TechTree.BBH.Capsule,
      define_field: false,
      foreign_key: :capsule_id,
      references: :capsule_id,
      type: :string

    has_many :runs, TechTree.BBH.Run, foreign_key: :assignment_ref, references: :assignment_ref

    timestamps()
  end

  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [
      :assignment_ref,
      :capsule_id,
      :split,
      :status,
      :agent_wallet_address,
      :agent_token_id,
      :origin,
      :completed_at
    ])
    |> validate_required([:assignment_ref, :capsule_id, :split, :status, :origin])
    |> check_constraint(:status, name: :bbh_assignments_status_check)
  end
end

defmodule TechTree.BBH.Genome do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:genome_id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "bbh_genomes" do
    field :label, :string
    field :parent_genome_ref, :string
    field :model_id, :string
    field :harness_type, :string
    field :harness_version, :string
    field :prompt_pack_version, :string
    field :skill_pack_version, :string
    field :tool_profile, :string
    field :runtime_image, :string
    field :helper_code_hash, :string
    field :data_profile, :string
    field :axes, :map, default: %{}
    field :notes, :string
    field :normalized_bundle_hash, :string
    field :source, :map, default: %{}

    has_many :runs, TechTree.BBH.Run, foreign_key: :genome_id, references: :genome_id

    timestamps()
  end

  def changeset(genome, attrs) do
    genome
    |> cast(attrs, [
      :genome_id,
      :label,
      :parent_genome_ref,
      :model_id,
      :harness_type,
      :harness_version,
      :prompt_pack_version,
      :skill_pack_version,
      :tool_profile,
      :runtime_image,
      :helper_code_hash,
      :data_profile,
      :axes,
      :notes,
      :normalized_bundle_hash,
      :source
    ])
    |> validate_required([
      :genome_id,
      :model_id,
      :harness_type,
      :harness_version,
      :prompt_pack_version,
      :skill_pack_version,
      :tool_profile,
      :runtime_image,
      :normalized_bundle_hash,
      :source
    ])
    |> unique_constraint(:normalized_bundle_hash)
  end
end

defmodule TechTree.BBH.Run do
  @moduledoc false
  use TechTree.Schema

  @statuses [:validation_pending, :running, :failed, :validated, :rejected]

  @primary_key {:run_id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "bbh_runs" do
    field :capsule_id, :string
    field :assignment_ref, :string
    field :genome_id, :string
    field :canonical_run_id, :string
    field :executor_type, :string
    field :harness_type, :string
    field :harness_version, :string
    field :split, :string
    field :status, Ecto.Enum, values: @statuses
    field :raw_score, :float
    field :normalized_score, :float
    field :score_source, :string
    field :analysis_py, :string
    field :protocol_md, :string
    field :rubric_json, :map, default: %{}
    field :task_json, :map, default: %{}
    field :verdict_json, :map, default: %{}
    field :final_answer_md, :string
    field :report_html, :string
    field :run_log, :string
    field :artifact_source, :map
    field :genome_source, :map, default: %{}
    field :run_source, :map, default: %{}

    belongs_to :capsule, TechTree.BBH.Capsule,
      define_field: false,
      foreign_key: :capsule_id,
      references: :capsule_id,
      type: :string

    belongs_to :assignment, TechTree.BBH.Assignment,
      define_field: false,
      foreign_key: :assignment_ref,
      references: :assignment_ref,
      type: :string

    belongs_to :genome, TechTree.BBH.Genome,
      define_field: false,
      foreign_key: :genome_id,
      references: :genome_id,
      type: :string

    has_many :validations, TechTree.BBH.Validation, foreign_key: :run_id, references: :run_id

    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :run_id,
      :capsule_id,
      :assignment_ref,
      :genome_id,
      :canonical_run_id,
      :executor_type,
      :harness_type,
      :harness_version,
      :split,
      :status,
      :raw_score,
      :normalized_score,
      :score_source,
      :analysis_py,
      :protocol_md,
      :rubric_json,
      :task_json,
      :verdict_json,
      :final_answer_md,
      :report_html,
      :run_log,
      :artifact_source,
      :genome_source,
      :run_source
    ])
    |> validate_required([
      :run_id,
      :capsule_id,
      :genome_id,
      :executor_type,
      :harness_type,
      :harness_version,
      :split,
      :status,
      :analysis_py,
      :protocol_md,
      :rubric_json,
      :task_json,
      :verdict_json,
      :genome_source,
      :run_source
    ])
    |> check_constraint(:status, name: :bbh_runs_status_check)
  end
end

defmodule TechTree.BBH.Validation do
  @moduledoc false
  use TechTree.Schema

  @roles [:official, :community]
  @methods [:replay, :manual, :replication]
  @results [:confirmed, :rejected, :mixed, :needs_revision]

  @primary_key {:validation_id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "bbh_validations" do
    field :run_id, :string
    field :canonical_review_id, :string
    field :role, Ecto.Enum, values: @roles
    field :method, Ecto.Enum, values: @methods
    field :result, Ecto.Enum, values: @results
    field :reproduced_raw_score, :float
    field :reproduced_normalized_score, :float
    field :tolerance_raw_abs, :float
    field :summary, :string
    field :review_source, :map, default: %{}
    field :verdict_json, :map
    field :report_html, :string
    field :run_log, :string

    belongs_to :run, TechTree.BBH.Run,
      define_field: false,
      foreign_key: :run_id,
      references: :run_id,
      type: :string

    timestamps()
  end

  def changeset(validation, attrs) do
    validation
    |> cast(attrs, [
      :validation_id,
      :run_id,
      :canonical_review_id,
      :role,
      :method,
      :result,
      :reproduced_raw_score,
      :reproduced_normalized_score,
      :tolerance_raw_abs,
      :summary,
      :review_source,
      :verdict_json,
      :report_html,
      :run_log
    ])
    |> validate_required([
      :validation_id,
      :run_id,
      :role,
      :method,
      :result,
      :summary,
      :review_source,
      :tolerance_raw_abs
    ])
    |> check_constraint(:role, name: :bbh_validations_role_check)
    |> check_constraint(:method, name: :bbh_validations_method_check)
    |> check_constraint(:result, name: :bbh_validations_result_check)
  end
end
