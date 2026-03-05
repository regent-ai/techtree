defmodule TechTree.XMTPMirror do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Accounts
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Accounts.HumanUser
  alias TechTree.Repo
  alias TechTree.XMTPMirror.{XmtpRoom, XmtpMessage, XmtpMembershipCommand}

  @canonical_room_key "public-trollbox"
  @inflight_statuses ["pending", "processing"]
  @max_message_length 2_000

  @type enqueue_result :: :queued | :already_pending | :already_applied

  @spec list_public_messages(map()) :: [XmtpMessage.t()]
  def list_public_messages(params) do
    limit = parse_limit(params, 100)

    XmtpMessage
    |> join(:inner, [m], r in XmtpRoom, on: r.id == m.room_id)
    |> join(:left, [m, _r], h in HumanUser, on: h.xmtp_inbox_id == m.sender_inbox_id)
    |> join(:left, [m, _r, _h], a in AgentIdentity,
      on: fragment("lower(?) = lower(?)", a.wallet_address, m.sender_wallet_address)
    )
    |> where([_m, r], r.room_key == ^@canonical_room_key)
    |> where([m, _r, _h, _a], m.moderation_state != "hidden")
    |> where([m, _r, h, _a], m.sender_type != :human or is_nil(h.id) or h.role != "banned")
    |> where([m, _r, _h, a], m.sender_type != :agent or is_nil(a.id) or a.status == "active")
    |> order_by([m], desc: m.sent_at, desc: m.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec request_join(TechTree.Accounts.HumanUser.t(), map()) ::
          {:ok, map()} | {:error, :xmtp_inbox_already_bound | Ecto.Changeset.t()}
  def request_join(human, attrs \\ %{}) do
    with {:ok, refreshed_human} <- maybe_assign_inbox_id(human, attrs),
         room <- canonical_room() do
      case enqueue_canonical_membership_op(refreshed_human, "add_member") do
        {:ok, :queued} ->
          {:ok, join_status_payload("pending", refreshed_human.id, room)}

        {:ok, :already_pending} ->
          {:ok, join_status_payload("pending", refreshed_human.id, room)}

        {:ok, :already_applied} ->
          {:ok, join_status_payload("joined", refreshed_human.id, room)}

        {:error, :room_unavailable} ->
          {:ok, join_status_payload("room_unavailable", refreshed_human.id, room)}

        {:error, :missing_inbox_id} ->
          {:ok, join_status_payload("missing_inbox_id", refreshed_human.id, room)}
      end
    end
  end

  @spec create_human_message(TechTree.Accounts.HumanUser.t(), map()) ::
          {:ok, XmtpMessage.t()}
          | {:error, :room_unavailable | :missing_inbox_id | :membership_required | :body_required | :body_too_long | :xmtp_inbox_already_bound | Ecto.Changeset.t()}
  def create_human_message(human, attrs) when is_map(attrs) do
    with {:ok, body} <- normalize_message_body(attrs),
         {:ok, refreshed_human} <- maybe_assign_inbox_id(human, attrs),
         {:ok, room} <- fetch_active_canonical_room(),
         :ok <- ensure_joined_membership(refreshed_human),
         {:ok, message} <- insert_human_message(room, refreshed_human, body, attrs) do
      {:ok, message}
    end
  end

  @spec membership_for(TechTree.Accounts.HumanUser.t()) :: map()
  def membership_for(human) do
    case canonical_room() do
      %XmtpRoom{status: "active"} = room ->
        case normalized_inbox_id(human.xmtp_inbox_id) do
          nil ->
            %{
              human_id: human.id,
              room_key: @canonical_room_key,
              shard_key: @canonical_room_key,
              xmtp_group_id: room.xmtp_group_id,
              room_present: true,
              state: "missing_inbox_id"
            }

          inbox_id ->
            %{
              human_id: human.id,
              room_key: @canonical_room_key,
              shard_key: @canonical_room_key,
              xmtp_group_id: room.xmtp_group_id,
              room_present: true,
              state:
                room.id
                |> latest_membership_command(human.id, inbox_id)
                |> membership_state_from_command()
            }
        end

      _ ->
        %{
          human_id: human.id,
          room_key: @canonical_room_key,
          shard_key: @canonical_room_key,
          xmtp_group_id: nil,
          room_present: false,
          state: "room_unavailable"
        }
    end
  end

  @spec get_room_by_key(String.t()) :: XmtpRoom.t() | nil
  def get_room_by_key(room_key), do: Repo.get_by(XmtpRoom, room_key: room_key)

  @spec upsert_room(map()) :: {:ok, XmtpRoom.t()} | {:error, Ecto.Changeset.t()}
  def upsert_room(attrs) do
    room = Repo.get_by(XmtpRoom, room_key: attrs["room_key"] || attrs[:room_key]) || %XmtpRoom{}
    room |> XmtpRoom.changeset(attrs) |> Repo.insert_or_update()
  end

  @spec upsert_message(map()) :: {:ok, XmtpMessage.t()} | {:error, Ecto.Changeset.t()}
  def upsert_message(attrs) do
    message = Repo.get_by(XmtpMessage, xmtp_message_id: attrs["xmtp_message_id"] || attrs[:xmtp_message_id]) || %XmtpMessage{}
    message |> XmtpMessage.changeset(attrs) |> Repo.insert_or_update()
  end

  @spec lease_next_command(String.t()) :: XmtpMembershipCommand.t() | nil
  def lease_next_command(room_key) do
    case Repo.get_by(XmtpRoom, room_key: room_key) do
      nil ->
        nil

      room ->
        Repo.transaction(fn ->
          XmtpMembershipCommand
          |> where([c], c.room_id == ^room.id and c.status == "pending")
          |> order_by([c], asc: c.inserted_at, asc: c.id)
          |> lock("FOR UPDATE SKIP LOCKED")
          |> limit(1)
          |> Repo.one()
          |> case do
            nil ->
              nil

            command ->
              command
              |> XmtpMembershipCommand.processing_changeset()
              |> Repo.update!()
          end
        end)
        |> case do
          {:ok, command} -> command
          _ -> nil
        end
    end
  end

  @spec complete_command(integer() | String.t()) :: :ok
  def complete_command(id) do
    command = Repo.get!(XmtpMembershipCommand, normalize_id(id))
    command |> XmtpMembershipCommand.done_changeset() |> Repo.update!()
    :ok
  end

  @spec fail_command(integer() | String.t(), String.t()) :: :ok
  def fail_command(id, error) do
    command = Repo.get!(XmtpMembershipCommand, normalize_id(id))
    command |> XmtpMembershipCommand.failed_changeset(error) |> Repo.update!()
    :ok
  end

  @spec add_human_to_canonical_room(integer() | String.t()) :: :ok
  def add_human_to_canonical_room(human_id) do
    human = Repo.get!(HumanUser, normalize_id(human_id))

    case enqueue_canonical_membership_op(human, "add_member") do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "cannot enqueue add_member for human_user_id=#{human.id}: #{inspect(reason)}"
    end
  end

  @spec remove_human_from_canonical_room(integer() | String.t()) :: :ok
  def remove_human_from_canonical_room(human_id) do
    human = Repo.get!(HumanUser, normalize_id(human_id))

    case enqueue_canonical_membership_op(human, "remove_member") do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "cannot enqueue remove_member for human_user_id=#{human.id}: #{inspect(reason)}"
    end
  end

  @spec parse_limit(map(), pos_integer()) :: pos_integer()
  defp parse_limit(params, fallback) do
    case Map.get(params, "limit") do
      nil -> fallback
      value when is_integer(value) and value > 0 -> min(value, 200)
      value when is_binary(value) -> clamp_limit(String.to_integer(value), fallback)
      _ -> fallback
    end
  rescue
    _ -> fallback
  end

  @spec clamp_limit(integer(), pos_integer()) :: pos_integer()
  defp clamp_limit(value, fallback) when value <= 0, do: fallback
  defp clamp_limit(value, _fallback), do: min(value, 200)

  @spec normalize_id(integer() | String.t()) :: integer()
  defp normalize_id(value) when is_integer(value), do: value
  defp normalize_id(value) when is_binary(value), do: String.to_integer(value)

  @spec enqueue_canonical_membership_op(TechTree.Accounts.HumanUser.t(), String.t()) ::
          {:ok, enqueue_result()} | {:error, :room_unavailable | :missing_inbox_id}
  defp enqueue_canonical_membership_op(human, op) do
    case canonical_room() do
      %XmtpRoom{status: "active", id: room_id} ->
        case normalized_inbox_id(human.xmtp_inbox_id) do
          nil ->
            {:error, :missing_inbox_id}

          inbox_id ->
            Repo.transaction(fn ->
              lock_human!(human.id)

              case inflight_command(room_id, human.id, inbox_id, op) do
                %XmtpMembershipCommand{} ->
                  :already_pending

                nil ->
                  if operation_already_applied?(room_id, human.id, inbox_id, op) do
                    :already_applied
                  else
                    enqueue_membership_command!(room_id, human.id, inbox_id, op)
                    :queued
                  end
              end
            end)
            |> case do
              {:ok, result} -> {:ok, result}
              _ -> {:error, :room_unavailable}
            end
        end

      _ ->
        {:error, :room_unavailable}
    end
  end

  @spec canonical_room() :: XmtpRoom.t() | nil
  defp canonical_room, do: Repo.get_by(XmtpRoom, room_key: @canonical_room_key)

  @spec join_status_payload(String.t(), integer(), XmtpRoom.t() | nil) :: map()
  defp join_status_payload(status, human_id, room) do
    %{
      status: status,
      human_id: human_id,
      room_key: @canonical_room_key,
      shard_key: @canonical_room_key,
      xmtp_group_id: if(is_nil(room), do: nil, else: room.xmtp_group_id)
    }
  end

  @spec normalized_inbox_id(String.t() | nil) :: String.t() | nil
  defp normalized_inbox_id(nil), do: nil

  defp normalized_inbox_id(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalized_inbox_id(_value), do: nil

  @spec maybe_assign_inbox_id(HumanUser.t(), map()) ::
          {:ok, HumanUser.t()} | {:error, :xmtp_inbox_already_bound | Ecto.Changeset.t()}
  defp maybe_assign_inbox_id(%HumanUser{} = human, attrs) do
    supplied_inbox_id =
      Map.get(attrs, "xmtp_inbox_id")
      |> case do
        nil -> Map.get(attrs, :xmtp_inbox_id)
        value -> value
      end
      |> normalized_inbox_id()

    case {normalized_inbox_id(human.xmtp_inbox_id), supplied_inbox_id} do
      {_existing, nil} ->
        {:ok, human}

      {nil, inbox_id} ->
        case Accounts.update_human(human, %{xmtp_inbox_id: inbox_id}) do
          {:ok, updated_human} -> {:ok, updated_human}
          {:error, changeset} -> {:error, changeset}
        end

      {existing, inbox_id} when existing == inbox_id ->
        {:ok, human}

      {_existing, _inbox_id} ->
        {:error, :xmtp_inbox_already_bound}
    end
  end

  @spec fetch_active_canonical_room() :: {:ok, XmtpRoom.t()} | {:error, :room_unavailable}
  defp fetch_active_canonical_room do
    case canonical_room() do
      %XmtpRoom{status: "active"} = room -> {:ok, room}
      _ -> {:error, :room_unavailable}
    end
  end

  @spec ensure_joined_membership(HumanUser.t()) ::
          :ok | {:error, :membership_required | :missing_inbox_id | :room_unavailable}
  defp ensure_joined_membership(%HumanUser{} = human) do
    case membership_for(human) do
      %{state: "joined"} -> :ok
      %{state: "missing_inbox_id"} -> {:error, :missing_inbox_id}
      %{state: "room_unavailable"} -> {:error, :room_unavailable}
      _ -> {:error, :membership_required}
    end
  end

  @spec normalize_message_body(map()) :: {:ok, String.t()} | {:error, :body_required | :body_too_long}
  defp normalize_message_body(attrs) when is_map(attrs) do
    body =
      Map.get(attrs, "body")
      |> case do
        nil -> Map.get(attrs, :body)
        value -> value
      end

    cond do
      not is_binary(body) ->
        {:error, :body_required}

      true ->
        trimmed = String.trim(body)

        cond do
          trimmed == "" -> {:error, :body_required}
          String.length(trimmed) > @max_message_length -> {:error, :body_too_long}
          true -> {:ok, trimmed}
        end
    end
  end

  @spec insert_human_message(XmtpRoom.t(), HumanUser.t(), String.t(), map()) ::
          {:ok, XmtpMessage.t()} | {:error, Ecto.Changeset.t()}
  defp insert_human_message(%XmtpRoom{} = room, %HumanUser{} = human, body, attrs) do
    message_id =
      case Map.get(attrs, "xmtp_message_id") || Map.get(attrs, :xmtp_message_id) do
        nil -> "human-#{human.id}-#{System.unique_integer([:positive, :monotonic])}"
        value when is_binary(value) -> value
        value -> to_string(value)
      end

    display_label =
      case human.display_name do
        value when is_binary(value) and value != "" -> value
        _ -> "human:#{human.id}"
      end

    payload = %{
      room_id: room.id,
      xmtp_message_id: message_id,
      sender_inbox_id: human.xmtp_inbox_id,
      sender_wallet_address: human.wallet_address,
      sender_label: display_label,
      sender_type: :human,
      body: body,
      sent_at: DateTime.utc_now(),
      raw_payload: %{
        "source" => "humanbox",
        "human_user_id" => human.id
      },
      moderation_state: "visible"
    }

    %XmtpMessage{}
    |> XmtpMessage.changeset(payload)
    |> Repo.insert()
  end

  @spec lock_human!(integer()) :: HumanUser.t()
  defp lock_human!(human_id) do
    HumanUser
    |> where([h], h.id == ^human_id)
    |> lock("FOR UPDATE")
    |> limit(1)
    |> Repo.one!()
  end

  @spec inflight_command(integer(), integer(), String.t(), String.t()) :: XmtpMembershipCommand.t() | nil
  defp inflight_command(room_id, human_id, inbox_id, op) do
    XmtpMembershipCommand
    |> where(
      [c],
      c.room_id == ^room_id and c.human_user_id == ^human_id and c.xmtp_inbox_id == ^inbox_id and
        c.op == ^op and c.status in ^@inflight_statuses
    )
    |> order_by([c], desc: c.inserted_at, desc: c.id)
    |> limit(1)
    |> Repo.one()
  end

  @spec latest_membership_command(integer(), integer(), String.t()) :: XmtpMembershipCommand.t() | nil
  defp latest_membership_command(room_id, human_id, inbox_id) do
    XmtpMembershipCommand
    |> where([c], c.room_id == ^room_id and c.human_user_id == ^human_id and c.xmtp_inbox_id == ^inbox_id)
    |> order_by([c], desc: c.inserted_at, desc: c.id)
    |> limit(1)
    |> Repo.one()
  end

  @spec operation_already_applied?(integer(), integer(), String.t(), String.t()) :: boolean()
  defp operation_already_applied?(room_id, human_id, inbox_id, op) do
    case latest_membership_command(room_id, human_id, inbox_id) do
      %XmtpMembershipCommand{op: ^op, status: "done"} -> true
      _ -> false
    end
  end

  @spec enqueue_membership_command!(integer(), integer(), String.t(), String.t()) :: XmtpMembershipCommand.t()
  defp enqueue_membership_command!(room_id, human_id, inbox_id, op) do
    %XmtpMembershipCommand{}
    |> XmtpMembershipCommand.enqueue_changeset(%{
      room_id: room_id,
      human_user_id: human_id,
      op: op,
      xmtp_inbox_id: inbox_id
    })
    |> Repo.insert!()
  end

  @spec membership_state_from_command(XmtpMembershipCommand.t() | nil) :: String.t()
  defp membership_state_from_command(nil), do: "not_joined"
  defp membership_state_from_command(%XmtpMembershipCommand{op: "add_member", status: "done"}), do: "joined"
  defp membership_state_from_command(%XmtpMembershipCommand{op: "add_member", status: "failed"}), do: "join_failed"

  defp membership_state_from_command(%XmtpMembershipCommand{
         op: "add_member",
         status: status
       })
       when status in @inflight_statuses,
       do: "join_pending"

  defp membership_state_from_command(%XmtpMembershipCommand{
         op: "remove_member",
         status: "done"
       }),
       do: "not_joined"

  defp membership_state_from_command(%XmtpMembershipCommand{
         op: "remove_member",
         status: "failed"
       }),
       do: "leave_failed"

  defp membership_state_from_command(%XmtpMembershipCommand{
         op: "remove_member",
         status: status
       })
       when status in @inflight_statuses,
       do: "leave_pending"

  defp membership_state_from_command(_command), do: "unknown"
end
