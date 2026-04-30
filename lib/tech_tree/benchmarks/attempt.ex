defmodule TechTree.Benchmarks.Attempt do
  @moduledoc false
  use TechTree.Schema

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Benchmarks.{Capsule, CapsuleVersion, Harness, Validation}

  @statuses [
    :created,
    :running,
    :submitted,
    :scored,
    :validation_pending,
    :validated,
    :rejected,
    :failed
  ]
  @score_statuses [:unscored, :scored, :rejected]

  @primary_key {:attempt_id, :string, autogenerate: false}
  @foreign_key_type :string

  @type t :: %__MODULE__{}

  schema "benchmark_attempts" do
    field :capsule_id, :string
    field :version_id, :string
    field :harness_id, :string
    field :solver_wallet_address, :string
    field :repeat_group_id, :string
    field :attempt_ordinal, :integer, default: 1
    field :status, Ecto.Enum, values: @statuses, default: :submitted
    field :score_status, Ecto.Enum, values: @score_statuses, default: :unscored
    field :raw_score, :float
    field :normalized_score, :float
    field :score_source, :string
    field :solved, :boolean
    field :answer_text, :string
    field :answer_json, :map
    field :answer_hash, :string
    field :verdict_json, :map, default: %{}
    field :run_bundle_cid, :string
    field :run_bundle_sha256, :string
    field :solver_notebook_cid, :string
    field :report_cid, :string
    field :tool_calls_cid, :string
    field :log_cid, :string
    field :artifact_manifest, :map, default: %{}
    field :runtime_seconds, :integer
    field :cost_usd_micros, :integer
    field :tokens_input, :integer
    field :tokens_output, :integer
    field :tool_install_events_count, :integer, default: 0
    field :external_resource_call_count, :integer, default: 0
    field :run_source, :map, default: %{}
    field :workspace_source, :map, default: %{}
    field :submitted_at, :utc_datetime_usec
    field :validated_at, :utc_datetime_usec

    belongs_to :capsule, Capsule,
      define_field: false,
      foreign_key: :capsule_id,
      references: :capsule_id,
      type: :string

    belongs_to :version, CapsuleVersion,
      define_field: false,
      foreign_key: :version_id,
      references: :version_id,
      type: :string

    belongs_to :harness, Harness,
      define_field: false,
      foreign_key: :harness_id,
      references: :harness_id,
      type: :string

    belongs_to :solver_agent, AgentIdentity, type: :id

    has_many :validations, Validation,
      foreign_key: :attempt_id,
      references: :attempt_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :attempt_id,
      :capsule_id,
      :version_id,
      :harness_id,
      :solver_agent_id,
      :solver_wallet_address,
      :repeat_group_id,
      :attempt_ordinal,
      :status,
      :score_status,
      :raw_score,
      :normalized_score,
      :score_source,
      :solved,
      :answer_text,
      :answer_json,
      :answer_hash,
      :verdict_json,
      :run_bundle_cid,
      :run_bundle_sha256,
      :solver_notebook_cid,
      :report_cid,
      :tool_calls_cid,
      :log_cid,
      :artifact_manifest,
      :runtime_seconds,
      :cost_usd_micros,
      :tokens_input,
      :tokens_output,
      :tool_install_events_count,
      :external_resource_call_count,
      :run_source,
      :workspace_source,
      :submitted_at,
      :validated_at
    ])
    |> validate_required([
      :attempt_id,
      :capsule_id,
      :version_id,
      :harness_id,
      :repeat_group_id,
      :attempt_ordinal,
      :status,
      :score_status,
      :verdict_json,
      :artifact_manifest,
      :tool_install_events_count,
      :external_resource_call_count,
      :run_source,
      :workspace_source
    ])
    |> validate_number(:attempt_ordinal, greater_than_or_equal_to: 1)
    |> validate_number(:runtime_seconds, greater_than_or_equal_to: 0)
    |> validate_number(:cost_usd_micros, greater_than_or_equal_to: 0)
    |> validate_number(:tokens_input, greater_than_or_equal_to: 0)
    |> validate_number(:tokens_output, greater_than_or_equal_to: 0)
    |> validate_number(:tool_install_events_count, greater_than_or_equal_to: 0)
    |> validate_number(:external_resource_call_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:capsule_id)
    |> foreign_key_constraint(:version_id)
    |> foreign_key_constraint(:harness_id)
    |> foreign_key_constraint(:solver_agent_id)
    |> check_constraint(:status, name: :benchmark_attempts_status_check)
    |> check_constraint(:score_status, name: :benchmark_attempts_score_status_check)
  end

  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @spec score_statuses() :: [atom()]
  def score_statuses, do: @score_statuses
end
