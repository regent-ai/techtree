defmodule TechTree.Autoskill.Review do
  use TechTree.Schema

  @moduledoc """
  Structured community and replicable reviews for autoskill skill versions.
  """

  schema "autoskill_reviews" do
    field :kind, Ecto.Enum, values: [:community, :replicable]
    field :rating, :float
    field :note, :string
    field :runtime_kind, Ecto.Enum, values: [:local, :molab, :wasm, :self_hosted]
    field :reported_score, :float
    field :details, :map, default: %{}

    belongs_to :skill_node, TechTree.Nodes.Node
    belongs_to :reviewer_agent, TechTree.Agents.AgentIdentity
    belongs_to :result, TechTree.Autoskill.Result

    timestamps()
  end

  def changeset(review, attrs) do
    review
    |> cast(attrs, [
      :skill_node_id,
      :reviewer_agent_id,
      :kind,
      :result_id,
      :rating,
      :note,
      :runtime_kind,
      :reported_score,
      :details
    ])
    |> validate_required([:skill_node_id, :reviewer_agent_id, :kind])
    |> validate_kind_shape()
    |> check_constraint(:kind, name: :autoskill_reviews_kind_check)
    |> check_constraint(:runtime_kind, name: :autoskill_reviews_runtime_kind_check)
    |> foreign_key_constraint(:skill_node_id)
    |> foreign_key_constraint(:reviewer_agent_id)
    |> foreign_key_constraint(:result_id)
    |> unique_constraint(
      [:skill_node_id, :reviewer_agent_id, :kind, :result_id],
      name: :autoskill_reviews_dedupe_idx
    )
  end

  defp validate_kind_shape(changeset) do
    case get_field(changeset, :kind) do
      :community ->
        validate_required(changeset, [:rating])

      :replicable ->
        changeset
        |> validate_required([:result_id, :runtime_kind, :reported_score])

      _ ->
        changeset
    end
  end
end
