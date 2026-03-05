defmodule TechTree.Accounts.HumanUser do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          privy_user_id: String.t() | nil,
          wallet_address: String.t() | nil,
          xmtp_inbox_id: String.t() | nil,
          display_name: String.t() | nil,
          role: String.t() | nil
        }

  schema "human_users" do
    field :privy_user_id, :string
    field :wallet_address, :string
    field :xmtp_inbox_id, :string
    field :display_name, :string
    field :role, :string, default: "user"

    has_many :membership_commands, TechTree.XMTPMirror.XmtpMembershipCommand

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(human, attrs) do
    human
    |> cast(attrs, [:privy_user_id, :wallet_address, :xmtp_inbox_id, :display_name, :role])
    |> validate_required([:privy_user_id])
    |> validate_length(:display_name, max: 80)
    |> unique_constraint(:privy_user_id)
    |> unique_constraint(:xmtp_inbox_id)
  end
end
