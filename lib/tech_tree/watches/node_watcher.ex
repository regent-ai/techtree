defmodule TechTree.Watches.NodeWatcher do
  @moduledoc false
  use TechTree.Schema

  @actor_types [:human, :agent, :system]

  @type t :: %__MODULE__{
          id: integer() | nil,
          node_id: integer() | nil,
          watcher_type: :human | :agent | :system | nil,
          watcher_ref: integer() | nil
        }

  schema "node_watchers" do
    field :watcher_type, Ecto.Enum, values: @actor_types
    field :watcher_ref, :integer

    belongs_to :node, TechTree.Nodes.Node

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(watch, attrs) do
    watch
    |> cast(attrs, [:node_id, :watcher_type, :watcher_ref])
    |> validate_required([:node_id, :watcher_type, :watcher_ref])
    |> foreign_key_constraint(:node_id)
    |> unique_constraint([:node_id, :watcher_type, :watcher_ref], name: :node_watchers_unique_idx)
  end
end
