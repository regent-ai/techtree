defmodule TechTree.XMTPMirror.XmtpMessage do
  @moduledoc false

  use TechTree.Schema

  @sender_types [:human, :agent, :system]

  @type t :: %__MODULE__{
          id: integer() | nil,
          room_id: integer() | nil,
          xmtp_message_id: String.t() | nil,
          sender_inbox_id: String.t() | nil,
          sender_wallet_address: String.t() | nil,
          sender_label: String.t() | nil,
          sender_type: :human | :agent | :system | nil,
          body: String.t() | nil,
          sent_at: DateTime.t() | nil,
          raw_payload: map(),
          moderation_state: String.t() | nil,
          reply_to_message_id: integer() | nil,
          reactions: map()
        }

  schema "xmtp_messages" do
    field :xmtp_message_id, :string
    field :sender_inbox_id, :string
    field :sender_wallet_address, :string
    field :sender_label, :string
    field :sender_type, Ecto.Enum, values: @sender_types
    field :body, :string
    field :sent_at, :utc_datetime_usec
    field :raw_payload, :map, default: %{}
    field :moderation_state, :string, default: "visible"
    field :reply_to_message_id, :id
    field :reactions, :map, default: %{}

    belongs_to :room, TechTree.XMTPMirror.XmtpRoom

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
    |> validate_required([
      :room_id,
      :xmtp_message_id,
      :sender_inbox_id,
      :sender_type,
      :body,
      :sent_at
    ])
    |> validate_length(:xmtp_message_id, min: 1, max: 160)
    |> validate_length(:sender_inbox_id, min: 1, max: 160)
    |> validate_length(:sender_wallet_address, max: 128)
    |> validate_length(:sender_label, max: 160)
    |> validate_length(:body, min: 1, max: 10_000)
    |> validate_length(:moderation_state, max: 32)
    |> foreign_key_constraint(:room_id)
    |> foreign_key_constraint(:reply_to_message_id)
    |> unique_constraint(:xmtp_message_id)
  end
end
