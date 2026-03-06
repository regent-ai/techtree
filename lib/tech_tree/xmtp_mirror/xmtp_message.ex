defmodule TechTree.XMTPMirror.XmtpMessage do
  @moduledoc false
  use TechTree.Schema

  @actor_types [:human, :agent, :system]

  @type t :: %__MODULE__{
          id: integer() | nil,
          room_id: integer() | nil,
          reply_to_message_id: integer() | nil,
          xmtp_message_id: String.t() | nil,
          sender_inbox_id: String.t() | nil,
          sender_wallet_address: String.t() | nil,
          sender_label: String.t() | nil,
          sender_type: :human | :agent | :system | nil,
          body: String.t() | nil,
          sent_at: DateTime.t() | nil,
          raw_payload: map(),
          moderation_state: String.t() | nil,
          reactions: map()
        }

  schema "xmtp_messages" do
    field :xmtp_message_id, :string
    field :sender_inbox_id, :string
    field :sender_wallet_address, :string
    field :sender_label, :string
    field :sender_type, Ecto.Enum, values: @actor_types
    field :body, :string
    field :sent_at, :utc_datetime_usec
    field :raw_payload, :map, default: %{}
    field :moderation_state, :string, default: "visible"
    field :reactions, :map, default: %{}

    belongs_to :room, TechTree.XMTPMirror.XmtpRoom
    belongs_to :reply_to_message, __MODULE__

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :room_id,
      :xmtp_message_id,
      :sender_inbox_id,
      :sender_wallet_address,
      :sender_label,
      :sender_type,
      :body,
      :sent_at,
      :raw_payload,
      :moderation_state,
      :reply_to_message_id,
      :reactions
    ])
    |> validate_required([:room_id, :xmtp_message_id, :sender_inbox_id, :body, :sent_at])
    |> foreign_key_constraint(:room_id)
    |> foreign_key_constraint(:reply_to_message_id)
    |> unique_constraint(:xmtp_message_id)
  end
end
