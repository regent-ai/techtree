defmodule TechTree.XMTPMirror.XmtpRoom do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          room_key: String.t() | nil,
          xmtp_group_id: String.t() | nil,
          name: String.t() | nil,
          status: String.t() | nil,
          presence_ttl_seconds: integer()
        }

  schema "xmtp_rooms" do
    field :room_key, :string
    field :xmtp_group_id, :string
    field :name, :string
    field :status, :string, default: "active"
    field :presence_ttl_seconds, :integer, default: 120

    has_many :messages, TechTree.XMTPMirror.XmtpMessage, foreign_key: :room_id

    has_many :membership_commands, TechTree.XMTPMirror.XmtpMembershipCommand,
      foreign_key: :room_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:room_key, :xmtp_group_id, :name, :status, :presence_ttl_seconds])
    |> validate_required([:room_key, :name])
    |> validate_number(:presence_ttl_seconds,
      greater_than_or_equal_to: 15,
      less_than_or_equal_to: 3600
    )
    |> unique_constraint(:room_key)
    |> unique_constraint(:xmtp_group_id)
  end
end
