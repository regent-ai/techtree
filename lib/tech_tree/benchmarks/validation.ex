defmodule TechTree.Benchmarks.Validation do
  @moduledoc false
  use TechTree.Schema

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Benchmarks.{Attempt, Capsule}
  alias TechTree.Nodes.Node

  @roles [:official, :community, :reviewer, :author, :oracle]
  @methods [:replay, :manual, :replication, :oracle, :hidden_truth_check]
  @results [:confirmed, :rejected, :mixed, :needs_revision, :inconclusive]

  @primary_key {:validation_id, :string, autogenerate: false}
  @foreign_key_type :string

  @type t :: %__MODULE__{}

  schema "benchmark_validations" do
    field :attempt_id, :string
    field :capsule_id, :string
    field :validator_wallet_address, :string
    field :role, Ecto.Enum, values: @roles
    field :method, Ecto.Enum, values: @methods
    field :result, Ecto.Enum, values: @results
    field :reproduced_raw_score, :float
    field :reproduced_normalized_score, :float
    field :tolerance_raw_abs, :float, default: 0.01
    field :summary_md, :string
    field :validation_notebook_cid, :string
    field :verdict_json, :map, default: %{}
    field :review_source, :map, default: %{}
    field :chain_tx_hash, :string
    field :chain_id, :integer

    belongs_to :attempt, Attempt,
      define_field: false,
      foreign_key: :attempt_id,
      references: :attempt_id,
      type: :string

    belongs_to :capsule, Capsule,
      define_field: false,
      foreign_key: :capsule_id,
      references: :capsule_id,
      type: :string

    belongs_to :validator_agent, AgentIdentity, type: :id
    belongs_to :review_node, Node, type: :id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(validation, attrs) do
    validation
    |> cast(attrs, [
      :validation_id,
      :attempt_id,
      :capsule_id,
      :validator_agent_id,
      :validator_wallet_address,
      :role,
      :method,
      :result,
      :reproduced_raw_score,
      :reproduced_normalized_score,
      :tolerance_raw_abs,
      :summary_md,
      :validation_notebook_cid,
      :verdict_json,
      :review_source,
      :review_node_id,
      :chain_tx_hash,
      :chain_id
    ])
    |> validate_required([
      :validation_id,
      :attempt_id,
      :capsule_id,
      :role,
      :method,
      :result,
      :tolerance_raw_abs,
      :summary_md,
      :verdict_json,
      :review_source
    ])
    |> validate_number(:tolerance_raw_abs, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:attempt_id)
    |> foreign_key_constraint(:capsule_id)
    |> foreign_key_constraint(:validator_agent_id)
    |> foreign_key_constraint(:review_node_id)
    |> check_constraint(:role, name: :benchmark_validations_role_check)
    |> check_constraint(:method, name: :benchmark_validations_method_check)
    |> check_constraint(:result, name: :benchmark_validations_result_check)
  end

  @spec official_rejection?(t()) :: boolean()
  def official_rejection?(%__MODULE__{role: :official, result: :rejected}), do: true
  def official_rejection?(_validation), do: false

  @spec roles() :: [atom()]
  def roles, do: @roles

  @spec methods() :: [atom()]
  def methods, do: @methods

  @spec results() :: [atom()]
  def results, do: @results
end
