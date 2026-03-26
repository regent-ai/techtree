defmodule TechTree.Autoskill.Result do
  use TechTree.Schema

  @moduledoc """
  Stores one scored autoskill run of a skill version against an eval scenario.
  """

  schema "autoskill_results" do
    field :runtime_kind, Ecto.Enum, values: [:local, :molab, :wasm, :self_hosted]
    field :status, Ecto.Enum, values: [:complete, :failed], default: :complete
    field :trial_count, :integer, default: 1
    field :raw_score, :float
    field :normalized_score, :float
    field :grader_breakdown, :map, default: %{}
    field :artifacts, :map, default: %{}
    field :repro_manifest, :map, default: %{}

    belongs_to :skill_node, TechTree.Nodes.Node
    belongs_to :eval_node, TechTree.Nodes.Node
    belongs_to :executor_agent, TechTree.Agents.AgentIdentity

    timestamps()
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, [
      :skill_node_id,
      :eval_node_id,
      :executor_agent_id,
      :runtime_kind,
      :status,
      :trial_count,
      :raw_score,
      :normalized_score,
      :grader_breakdown,
      :artifacts,
      :repro_manifest
    ])
    |> validate_required([
      :skill_node_id,
      :eval_node_id,
      :executor_agent_id,
      :runtime_kind,
      :trial_count,
      :raw_score,
      :normalized_score
    ])
    |> validate_number(:trial_count, greater_than_or_equal_to: 1)
    |> foreign_key_constraint(:skill_node_id)
    |> foreign_key_constraint(:eval_node_id)
    |> foreign_key_constraint(:executor_agent_id)
  end
end
