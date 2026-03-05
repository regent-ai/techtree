defmodule TechTree.Activity.ActivityEvent do
  @moduledoc false
  use TechTree.Schema

  @actor_types [:human, :agent, :system]

  @type t :: %__MODULE__{
          id: integer() | nil,
          subject_node_id: integer() | nil,
          actor_type: :human | :agent | :system | nil,
          actor_ref: integer() | nil,
          event_type: String.t() | nil,
          payload: map()
        }

  schema "activity_events" do
    field :actor_type, Ecto.Enum, values: @actor_types
    field :actor_ref, :integer
    field :event_type, :string
    field :payload, :map, default: %{}

    belongs_to :subject_node, TechTree.Nodes.Node

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:subject_node_id, :actor_type, :actor_ref, :event_type, :payload])
    |> validate_required([:actor_type, :event_type])
    |> foreign_key_constraint(:subject_node_id)
  end
end
