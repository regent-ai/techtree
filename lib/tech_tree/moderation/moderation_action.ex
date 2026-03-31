defmodule TechTree.Moderation.ModerationAction do
  @moduledoc false
  use TechTree.Schema

  @targets [:node, :comment, :chatbox_message, :agent, :human]
  @actor_types [:human, :agent, :system]

  @type target :: :node | :comment | :chatbox_message | :agent | :human
  @type actor_type :: :human | :agent | :system

  @type t :: %__MODULE__{
          id: integer() | nil,
          target_type: target() | nil,
          target_ref: integer() | nil,
          action: String.t() | nil,
          reason: String.t() | nil,
          actor_type: actor_type() | nil,
          actor_ref: integer() | nil,
          payload: map()
        }

  schema "moderation_actions" do
    field :target_type, Ecto.Enum, values: @targets
    field :target_ref, :integer
    field :action, :string
    field :reason, :string
    field :actor_type, Ecto.Enum, values: @actor_types
    field :actor_ref, :integer
    field :payload, :map, default: %{}

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(action, attrs) do
    action
    |> cast(attrs, [
      :target_type,
      :target_ref,
      :action,
      :reason,
      :actor_type,
      :actor_ref,
      :payload
    ])
    |> validate_required([:target_type, :target_ref, :action, :actor_type])
  end
end
