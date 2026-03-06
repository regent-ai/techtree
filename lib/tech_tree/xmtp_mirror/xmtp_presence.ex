defmodule TechTree.XMTPMirror.XmtpPresence do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          room_id: integer() | nil,
          human_user_id: integer() | nil,
          xmtp_inbox_id: String.t() | nil,
          last_seen_at: DateTime.t() | nil,
          expires_at: DateTime.t() | nil,
          evicted_at: DateTime.t() | nil
        }

  schema "xmtp_presence_heartbeats" do
    field :xmtp_inbox_id, :string
    field :last_seen_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :evicted_at, :utc_datetime_usec

    belongs_to :room, TechTree.XMTPMirror.XmtpRoom
    belongs_to :human_user, TechTree.Accounts.HumanUser

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(presence, attrs) do
    presence
    |> cast(attrs, [
      :room_id,
      :human_user_id,
      :xmtp_inbox_id,
      :last_seen_at,
      :expires_at,
      :evicted_at
    ])
    |> validate_required([:room_id, :human_user_id, :xmtp_inbox_id, :last_seen_at, :expires_at])
    |> foreign_key_constraint(:room_id)
    |> foreign_key_constraint(:human_user_id)
    |> unique_constraint(:xmtp_inbox_id, name: :xmtp_presence_heartbeats_room_inbox_uidx)
  end
end
