defmodule TechTree.Trollbox.MessageReaction do
  @moduledoc false

  use TechTree.Schema

  @actor_kinds [:human, :agent]

  @type t :: %__MODULE__{
          id: integer() | nil,
          message_id: integer() | nil,
          actor_kind: :human | :agent | nil,
          actor_ref: integer() | nil,
          reaction: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "trollbox_message_reactions" do
    field :actor_kind, Ecto.Enum, values: @actor_kinds
    field :actor_ref, :integer
    field :reaction, :string

    belongs_to :message, TechTree.Trollbox.Message

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:message_id, :actor_kind, :actor_ref, :reaction])
    |> validate_required([:message_id, :actor_kind, :actor_ref, :reaction])
    |> validate_length(:reaction, max: 32)
    |> foreign_key_constraint(:message_id)
    |> unique_constraint(:reaction,
      name: :trollbox_message_reactions_message_actor_reaction_uidx
    )
  end
end
