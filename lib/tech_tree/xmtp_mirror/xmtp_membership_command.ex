defmodule TechTree.XMTPMirror.XmtpMembershipCommand do
  @moduledoc false

  use TechTree.Schema

  @op_values ["add_member", "remove_member"]
  @status_values ["pending", "processing", "done", "failed"]

  @type t :: %__MODULE__{
          id: integer() | nil,
          room_id: integer() | nil,
          human_user_id: integer() | nil,
          op: String.t() | nil,
          xmtp_inbox_id: String.t() | nil,
          status: String.t() | nil,
          attempt_count: integer() | nil,
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
    |> put_change(:status, normalize_default_status(attrs))
    |> put_change(:attempt_count, normalize_default_attempt_count(attrs))
    |> validate_required([:room_id, :op, :xmtp_inbox_id])
    |> validate_inclusion(:op, @op_values)
    |> validate_inclusion(:status, @status_values)
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
    |> validate_length(:xmtp_inbox_id, min: 1, max: 160)
    |> validate_length(:last_error, max: 500)
    |> foreign_key_constraint(:room_id)
    |> foreign_key_constraint(:human_user_id)
    |> check_constraint(:op, name: :xmtp_membership_commands_op_check)
    |> check_constraint(:status, name: :xmtp_membership_commands_status_check)
  end

  @spec normalize_default_status(map()) :: String.t()
  defp normalize_default_status(attrs) do
    case value_for(attrs, "status") do
      nil ->
        "pending"

      value when is_binary(value) ->
        if String.trim(value) != "" do
          value
        else
          "pending"
        end

      _ ->
        "pending"
    end
  end

  @spec normalize_default_attempt_count(map()) :: integer()
  defp normalize_default_attempt_count(attrs) do
    case value_for(attrs, "attempt_count") do
      value when is_integer(value) and value >= 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {int, ""} when int >= 0 -> int
          _ -> 0
        end

      _ ->
        0
    end
  end

  @spec value_for(map(), String.t()) :: term()
  defp value_for(attrs, key) when is_map(attrs) and is_binary(key), do: Map.get(attrs, key)
end
