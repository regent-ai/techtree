defmodule TechTree.XMTPMirror.XmtpRoom do
  @moduledoc false

  use TechTree.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          room_key: String.t() | nil,
          xmtp_group_id: String.t() | nil,
          name: String.t() | nil,
          status: String.t() | nil,
          presence_ttl_seconds: integer() | nil,
          capacity: integer() | nil
        }

  schema "xmtp_rooms" do
    field :room_key, :string
    field :xmtp_group_id, :string
    field :name, :string
    field :status, :string, default: "active"
    field :presence_ttl_seconds, :integer, default: 120
    field :capacity, :integer, default: 200

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:room_key, :xmtp_group_id, :name, :status, :presence_ttl_seconds, :capacity])
    |> validate_required([:room_key, :name])
    |> validate_length(:room_key, min: 1, max: 128)
    |> validate_length(:xmtp_group_id, max: 160)
    |> validate_length(:name, min: 1, max: 160)
    |> validate_length(:status, max: 32)
    |> validate_number(:presence_ttl_seconds, greater_than_or_equal_to: 15)
    |> validate_number(:presence_ttl_seconds, less_than_or_equal_to: 3_600)
    |> validate_number(:capacity, equal_to: 200)
  end
end
