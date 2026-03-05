defmodule TechTree.XMTPMirror.XmtpRoom do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          room_key: String.t() | nil,
          xmtp_group_id: String.t() | nil,
          name: String.t() | nil,
          status: String.t() | nil
        }

  schema "xmtp_rooms" do
    field :room_key, :string
    field :xmtp_group_id, :string
    field :name, :string
    field :status, :string, default: "active"

    has_many :messages, TechTree.XMTPMirror.XmtpMessage, foreign_key: :room_id
    has_many :membership_commands, TechTree.XMTPMirror.XmtpMembershipCommand, foreign_key: :room_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:room_key, :xmtp_group_id, :name, :status])
    |> validate_required([:room_key, :name])
    |> unique_constraint(:room_key)
    |> unique_constraint(:xmtp_group_id)
  end
end
