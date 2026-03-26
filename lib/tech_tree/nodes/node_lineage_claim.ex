defmodule TechTree.Nodes.NodeLineageClaim do
  @moduledoc false
  use TechTree.Schema

  alias TechTree.Nodes.NodeCrossChainLink

  @type t :: %__MODULE__{
          id: integer() | nil,
          subject_node_id: integer() | nil,
          claimant_agent_id: integer() | nil,
          relation: String.t() | nil,
          target_chain_id: integer() | nil,
          target_node_ref: String.t() | nil,
          target_node_id: integer() | nil,
          note: String.t() | nil,
          withdrawn_at: DateTime.t() | nil
        }

  schema "node_lineage_claims" do
    field :relation, :string
    field :target_chain_id, :integer
    field :target_node_ref, :string
    field :note, :string
    field :withdrawn_at, :utc_datetime_usec

    belongs_to :subject_node, TechTree.Nodes.Node
    belongs_to :claimant_agent, TechTree.Agents.AgentIdentity
    belongs_to :target_node, TechTree.Nodes.Node

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(claim, attrs) do
    claim
    |> cast(attrs, [
      :subject_node_id,
      :claimant_agent_id,
      :relation,
      :target_chain_id,
      :target_node_ref,
      :target_node_id,
      :note,
      :withdrawn_at
    ])
    |> validate_required([
      :subject_node_id,
      :claimant_agent_id,
      :relation,
      :target_chain_id,
      :target_node_ref
    ])
    |> validate_inclusion(:relation, NodeCrossChainLink.relations())
    |> validate_number(:target_chain_id, greater_than: 0)
    |> validate_length(:target_node_ref, min: 1, max: 512)
    |> validate_length(:note, max: 2_000)
    |> foreign_key_constraint(:subject_node_id)
    |> foreign_key_constraint(:claimant_agent_id)
    |> foreign_key_constraint(:target_node_id)
    |> unique_constraint(:target_node_ref, name: :node_lineage_claims_active_dedupe_uidx)
    |> check_constraint(:relation, name: :node_lineage_claims_relation_check)
  end
end
