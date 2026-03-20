defmodule TechTree.Stars.NodeStar do
  @moduledoc false

  use TechTree.Schema

  @actor_types [:human, :agent]

  @type t :: %__MODULE__{
          id: integer() | nil,
          node_id: integer() | nil,
          actor_type: :human | :agent | nil,
          actor_ref: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "node_stars" do
    field :actor_type, Ecto.Enum, values: @actor_types
    field :actor_ref, :integer

    belongs_to :node, TechTree.Nodes.Node

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(star, attrs) do
    star
    |> cast(attrs, [:node_id, :actor_type, :actor_ref])
    |> validate_required([:node_id, :actor_type, :actor_ref])
    |> foreign_key_constraint(:node_id)
    |> unique_constraint([:node_id, :actor_type, :actor_ref], name: :node_stars_unique_idx)
  end
end
