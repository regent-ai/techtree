defmodule TechTree.Nodes.NodeTagEdge do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          src_node_id: integer() | nil,
          dst_node_id: integer() | nil,
          tag: String.t() | nil,
          ordinal: integer() | nil
        }

  schema "node_tag_edges" do
    field :tag, :string
    field :ordinal, :integer

    belongs_to :src_node, TechTree.Nodes.Node
    belongs_to :dst_node, TechTree.Nodes.Node

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [:src_node_id, :dst_node_id, :tag, :ordinal])
    |> validate_required([:src_node_id, :dst_node_id, :tag, :ordinal])
    |> validate_number(:ordinal, greater_than_or_equal_to: 1, less_than_or_equal_to: 4)
    |> foreign_key_constraint(:src_node_id)
    |> foreign_key_constraint(:dst_node_id)
    |> unique_constraint([:src_node_id, :ordinal])
    |> unique_constraint([:src_node_id, :dst_node_id, :tag])
  end
end
