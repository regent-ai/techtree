defmodule TechTree.XMTPMirror.XmtpMembershipCommand do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          room_id: integer() | nil,
          human_user_id: integer() | nil,
          op: String.t() | nil,
          xmtp_inbox_id: String.t() | nil,
          status: String.t() | nil,
          attempt_count: integer(),
          last_error: String.t() | nil
        }

  schema "xmtp_membership_commands" do
    field :op, :string
    field :xmtp_inbox_id, :string
    field :status, :string, default: "pending"
    field :attempt_count, :integer, default: 0
    field :last_error, :string

    belongs_to :room, TechTree.XMTPMirror.XmtpRoom
    belongs_to :human_user, TechTree.Accounts.HumanUser

    timestamps()
  end

  @spec enqueue_changeset(t(), map()) :: Ecto.Changeset.t()
  def enqueue_changeset(command, attrs) do
    command
    |> cast(attrs, [
      :room_id,
      :human_user_id,
      :op,
      :xmtp_inbox_id,
      :status,
      :attempt_count,
      :last_error
    ])
    |> validate_required([:room_id, :op, :xmtp_inbox_id])
    |> validate_inclusion(:op, ["add_member", "remove_member"])
    |> validate_inclusion(:status, ["pending", "processing", "done", "failed"])
    |> foreign_key_constraint(:room_id)
    |> foreign_key_constraint(:human_user_id)
  end

  @spec processing_changeset(t()) :: Ecto.Changeset.t()
  def processing_changeset(command) do
    change(command,
      status: "processing",
      attempt_count: command.attempt_count + 1,
      last_error: nil
    )
  end

  @spec resolve_changeset(t(), map()) :: Ecto.Changeset.t()
  def resolve_changeset(command, attrs) do
    status = attrs[:status] || attrs["status"]
    error = attrs[:error] || attrs["error"]

    case status do
      "done" ->
        change(command, status: "done", last_error: nil)

      "failed" ->
        change(command, status: "failed", last_error: error)
    end
  end
end
