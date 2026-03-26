defmodule TechTree.Nodes.NodeCrossChainLink do
  @moduledoc false
  use TechTree.Schema

  @relations ~w(reproduces fork_of adaptation_of promoted_from backported_from copy_of)
  @withdraw_reasons ~w(replaced cleared)

  @type t :: %__MODULE__{
          id: integer() | nil,
          node_id: integer() | nil,
          author_agent_id: integer() | nil,
          relation: String.t() | nil,
          target_chain_id: integer() | nil,
          target_node_ref: String.t() | nil,
          target_node_id: integer() | nil,
          note: String.t() | nil,
          withdrawn_at: DateTime.t() | nil,
          withdrawn_reason: String.t() | nil
        }

  schema "node_cross_chain_links" do
    field :relation, :string
    field :target_chain_id, :integer
    field :target_node_ref, :string
    field :note, :string
    field :withdrawn_at, :utc_datetime_usec
    field :withdrawn_reason, :string

    belongs_to :node, TechTree.Nodes.Node
    belongs_to :author_agent, TechTree.Agents.AgentIdentity
    belongs_to :target_node, TechTree.Nodes.Node

    timestamps()
  end

  @spec relations() :: [String.t()]
  def relations, do: @relations

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(link, attrs) do
    link
    |> cast(attrs, [
      :node_id,
      :author_agent_id,
      :relation,
      :target_chain_id,
      :target_node_ref,
      :target_node_id,
      :note,
      :withdrawn_at,
      :withdrawn_reason
    ])
    |> validate_required([
      :node_id,
      :author_agent_id,
      :relation,
      :target_chain_id,
      :target_node_ref
    ])
    |> validate_inclusion(:relation, @relations)
    |> validate_number(:target_chain_id, greater_than: 0)
    |> validate_length(:target_node_ref, min: 1, max: 512)
    |> validate_length(:note, max: 2_000)
    |> validate_inclusion(:withdrawn_reason, @withdraw_reasons)
    |> foreign_key_constraint(:node_id)
    |> foreign_key_constraint(:author_agent_id)
    |> foreign_key_constraint(:target_node_id)
    |> unique_constraint(:node_id, name: :node_cross_chain_links_active_node_uidx)
    |> check_constraint(:relation, name: :node_cross_chain_links_relation_check)
    |> check_constraint(:withdrawn_reason, name: :node_cross_chain_links_withdrawn_reason_check)
  end
end
