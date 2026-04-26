defmodule TechTree.XMTPMirror.Membership do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Accounts.HumanUser
  alias TechTree.QueryHelpers
  alias TechTree.Repo
  alias TechTree.XmtpIdentity
  alias TechTree.XMTPMirror.Rooms
  alias TechTree.XMTPMirror.XmtpMembershipCommand
  alias TechTree.XMTPMirror.XmtpPresence
  alias TechTree.XMTPMirror.XmtpRoom

  @spec lease_next_command(String.t() | integer() | nil) :: XmtpMembershipCommand.t() | nil
  def lease_next_command(room_key_or_id) do
    case Rooms.resolve_room(room_key_or_id) do
      nil ->
        nil

      %XmtpRoom{id: room_id} ->
        Repo.transaction(fn ->
          case pending_command_query(room_id) |> Repo.one() do
            nil ->
              nil

            %XmtpMembershipCommand{} = command ->
              command
              |> Ecto.Changeset.change(
                status: "processing",
                attempt_count: command.attempt_count + 1
              )
              |> Repo.update!()
          end
        end)
        |> case do
          {:ok, nil} -> nil
          {:ok, %XmtpMembershipCommand{} = command} -> command
          {:error, _reason} -> nil
        end
    end
  end

  @spec resolve_command(integer() | String.t(), map()) ::
          :ok | {:error, :invalid_resolution_status}
  def resolve_command(command_id, attrs) do
    command = Repo.get!(XmtpMembershipCommand, QueryHelpers.normalize_id(command_id))
    status = normalize_status(Rooms.value_for(attrs, :status))

    case status do
      "done" ->
        command
        |> Ecto.Changeset.change(status: "done", last_error: nil)
        |> Repo.update!()

        :ok

      "failed" ->
        command
        |> Ecto.Changeset.change(
          status: "failed",
          last_error: normalize_error_message(Rooms.value_for(attrs, :error))
        )
        |> Repo.update!()

        :ok

      _ ->
        {:error, :invalid_resolution_status}
    end
  end

  @spec request_join(HumanUser.t(), map()) ::
          {:ok, map()} | {:error, :room_not_found | :human_banned | :xmtp_identity_required}
  def request_join(%HumanUser{role: "banned"}, _attrs), do: {:error, :human_banned}

  def request_join(%HumanUser{} = human, attrs) when is_map(attrs) do
    with {:ok, inbox_id} <- require_human_inbox_id(human),
         {:ok, room} <- Rooms.resolve_join_room(attrs) do
      case membership_state_for(human, room) do
        "joined" ->
          {:ok, %{status: "joined", human_id: human.id, room_key: room.room_key}}

        "join_pending" ->
          {:ok, %{status: "pending", human_id: human.id, room_key: room.room_key}}

        "leave_pending" ->
          {:ok, %{status: "pending", human_id: human.id, room_key: room.room_key}}

        _ ->
          case create_membership_command(human, room, inbox_id, "add_member") do
            {:ok, _command} ->
              {:ok,
               %{
                 status: "pending",
                 human_id: human.id,
                 room_key: room.room_key,
                 shard_key: room.room_key
               }}

            {:error, reason} ->
              {:error, reason}
          end
      end
    end
  end

  @spec heartbeat_presence(HumanUser.t(), map()) ::
          {:ok, map()}
          | {:error,
             :human_banned | :room_not_found | :xmtp_identity_required | Ecto.Changeset.t()}
  def heartbeat_presence(%HumanUser{role: "banned"}, _attrs), do: {:error, :human_banned}

  def heartbeat_presence(%HumanUser{} = human, attrs) when is_map(attrs) do
    with {:ok, inbox_id} <- require_human_inbox_id(human),
         {:ok, room} <- Rooms.resolve_join_room(attrs) do
      now = DateTime.utc_now()

      expires_at =
        DateTime.add(
          now,
          room.presence_ttl_seconds || Rooms.default_presence_ttl_seconds(),
          :second
        )

      presence_attrs = %{
        room_id: room.id,
        human_user_id: human.id,
        xmtp_inbox_id: inbox_id,
        last_seen_at: now,
        expires_at: expires_at,
        evicted_at: nil
      }

      presence =
        case Repo.get_by(XmtpPresence,
               room_id: room.id,
               xmtp_inbox_id: presence_attrs.xmtp_inbox_id
             ) do
          nil ->
            %XmtpPresence{}
            |> XmtpPresence.changeset(presence_attrs)
            |> Repo.insert!()

          %XmtpPresence{} = existing ->
            existing
            |> XmtpPresence.changeset(presence_attrs)
            |> Repo.update!()
        end

      eviction_count = enqueue_expired_presence_evictions(room, now)

      {:ok,
       %{
         status: "alive",
         room_key: room.room_key,
         eviction_enqueued: eviction_count,
         presence_id: presence.id
       }}
    end
  end

  @spec membership_for(HumanUser.t()) :: map()
  def membership_for(%HumanUser{} = human) do
    room_key = Rooms.canonical_room_key()

    case Rooms.get_room_by_key(room_key) do
      nil ->
        %{
          human_id: human.id,
          room_key: room_key,
          room_present: false,
          state: "room_unavailable"
        }

      %XmtpRoom{} = room ->
        case require_human_inbox_id(human) do
          {:ok, _inbox_id} ->
            member_room = latest_public_membership_room(human) || room

            %{
              human_id: human.id,
              room_key: member_room.room_key,
              shard_key: member_room.room_key,
              room_present: true,
              state: membership_state_for(human, member_room)
            }

          {:error, :xmtp_identity_required} ->
            %{
              human_id: human.id,
              room_key: room.room_key,
              room_present: true,
              state: "setup_required"
            }
        end
    end
  end

  @spec add_human_to_canonical_room(integer() | String.t()) ::
          {:ok, :enqueued | :already_joined | :already_pending_join}
          | {:error, :human_not_found | :human_banned | :room_not_found | :xmtp_identity_required}
  def add_human_to_canonical_room(human_id) when is_integer(human_id) or is_binary(human_id) do
    with {:ok, human} <- fetch_human(human_id),
         {:ok, room} <- Rooms.resolve_join_room(%{}) do
      case membership_state_for(human, room) do
        "joined" ->
          {:ok, :already_joined}

        "join_pending" ->
          {:ok, :already_pending_join}

        _ ->
          case request_join(human, %{}) do
            {:ok, _result} -> {:ok, :enqueued}
            {:error, reason} -> {:error, reason}
          end
      end
    else
      {:error, :room_not_found} -> {:error, :room_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec remove_human_from_canonical_room(integer() | String.t() | HumanUser.t()) ::
          {:ok, :enqueued | :already_not_joined | :already_pending_removal}
          | {:error, :human_not_found | :human_banned | :room_not_found | :xmtp_identity_required}
  def remove_human_from_canonical_room(human_id)
      when is_integer(human_id) or is_binary(human_id) do
    with {:ok, human} <- fetch_human(human_id) do
      remove_human_from_canonical_room(human)
    end
  end

  def remove_human_from_canonical_room(%HumanUser{} = human) do
    case Rooms.resolve_join_room(%{}) do
      {:ok, room} ->
        case membership_state_for(human, room) do
          "not_joined" ->
            {:ok, :already_not_joined}

          "join_failed" ->
            {:ok, :already_not_joined}

          "leave_pending" ->
            {:ok, :already_pending_removal}

          _ ->
            with {:ok, inbox_id} <- require_human_room_inbox_id(human, room),
                 {:ok, _command} <-
                   create_membership_command(human, room, inbox_id, "remove_member") do
              {:ok, :enqueued}
            end
        end

      {:error, _} ->
        {:error, :room_not_found}
    end
  end

  @spec best_effort_remove_human_from_canonical_room(integer() | String.t()) :: :ok
  def best_effort_remove_human_from_canonical_room(human_id)
      when is_integer(human_id) or is_binary(human_id) do
    case remove_human_from_canonical_room(human_id) do
      {:ok, _status} -> :ok
      {:error, _reason} -> :ok
    end
  end

  @spec require_human_inbox_id(HumanUser.t()) ::
          {:ok, String.t()} | {:error, :xmtp_identity_required}
  def require_human_inbox_id(%HumanUser{} = human) do
    case XmtpIdentity.ready_inbox_id(human) do
      {:ok, inbox_id} -> {:ok, inbox_id}
      {:error, :wallet_address_required} -> {:error, :xmtp_identity_required}
      {:error, :xmtp_identity_required} -> {:error, :xmtp_identity_required}
    end
  end

  defp pending_command_query(room_id) do
    XmtpMembershipCommand
    |> where([c], c.room_id == ^room_id and c.status == "pending")
    |> order_by([c], asc: c.inserted_at, asc: c.id)
    |> lock("FOR UPDATE SKIP LOCKED")
    |> limit(1)
  end

  defp create_membership_command(%HumanUser{} = human, %XmtpRoom{} = room, inbox_id, op) do
    existing =
      XmtpMembershipCommand
      |> where(
        [c],
        c.room_id == ^room.id and c.human_user_id == ^human.id and c.op == ^op and
          c.status in ["pending", "processing"]
      )
      |> limit(1)
      |> Repo.one()

    if existing do
      {:ok, existing}
    else
      %XmtpMembershipCommand{}
      |> XmtpMembershipCommand.enqueue_changeset(%{
        room_id: room.id,
        human_user_id: human.id,
        op: op,
        xmtp_inbox_id: inbox_id,
        status: "pending"
      })
      |> Repo.insert()
    end
  end

  defp enqueue_expired_presence_evictions(%XmtpRoom{} = room, now) do
    XmtpPresence
    |> where(
      [p],
      p.room_id == ^room.id and is_nil(p.evicted_at) and p.expires_at <= ^now
    )
    |> Repo.all()
    |> Enum.reduce(0, fn presence, count ->
      case presence.evicted_at do
        nil ->
          _ = create_eviction_command(presence, room)

          _ =
            presence
            |> Ecto.Changeset.change(evicted_at: now)
            |> Repo.update!()

          count + 1

        _ ->
          count
      end
    end)
  end

  defp create_eviction_command(%XmtpPresence{} = presence, %XmtpRoom{} = room) do
    existing =
      XmtpMembershipCommand
      |> where(
        [c],
        c.room_id == ^room.id and c.human_user_id == ^presence.human_user_id and
          c.xmtp_inbox_id == ^presence.xmtp_inbox_id and c.op == "remove_member" and
          c.status in ["pending", "processing"]
      )
      |> limit(1)
      |> Repo.one()

    if existing do
      existing
    else
      %XmtpMembershipCommand{}
      |> XmtpMembershipCommand.enqueue_changeset(%{
        room_id: room.id,
        human_user_id: presence.human_user_id,
        op: "remove_member",
        xmtp_inbox_id: presence.xmtp_inbox_id,
        status: "pending"
      })
      |> Repo.insert!()
    end
  end

  defp membership_state_for(%HumanUser{} = human, %XmtpRoom{} = room) do
    latest =
      XmtpMembershipCommand
      |> where([c], c.room_id == ^room.id and c.human_user_id == ^human.id)
      |> order_by([c], desc: c.inserted_at, desc: c.id)
      |> limit(1)
      |> Repo.one()

    case latest do
      nil ->
        "not_joined"

      %XmtpMembershipCommand{op: "add_member", status: status}
      when status in ["pending", "processing"] ->
        "join_pending"

      %XmtpMembershipCommand{op: "add_member", status: "done"} ->
        "joined"

      %XmtpMembershipCommand{op: "add_member", status: "failed"} ->
        "join_failed"

      %XmtpMembershipCommand{op: "remove_member", status: status}
      when status in ["pending", "processing"] ->
        "leave_pending"

      %XmtpMembershipCommand{op: "remove_member", status: "done"} ->
        "not_joined"

      %XmtpMembershipCommand{op: "remove_member", status: "failed"} ->
        "leave_failed"

      _ ->
        "not_joined"
    end
  end

  defp latest_public_membership_room(%HumanUser{} = human) do
    canonical_room_key = Rooms.canonical_room_key()
    shard_prefix = "#{canonical_room_key}-shard-"

    XmtpMembershipCommand
    |> join(:inner, [command], room in XmtpRoom, on: room.id == command.room_id)
    |> where(
      [command, room],
      command.human_user_id == ^human.id and
        (room.room_key == ^canonical_room_key or like(room.room_key, ^"#{shard_prefix}%"))
    )
    |> order_by([command, _room], desc: command.inserted_at, desc: command.id)
    |> limit(1)
    |> select([_command, room], room)
    |> Repo.one()
  end

  defp require_human_room_inbox_id(%HumanUser{} = human, %XmtpRoom{} = room) do
    case require_human_inbox_id(human) do
      {:ok, inbox_id} ->
        {:ok, inbox_id}

      {:error, :xmtp_identity_required} ->
        case fallback_room_inbox_id(human, room) do
          nil -> {:error, :xmtp_identity_required}
          inbox_id -> {:ok, inbox_id}
        end
    end
  end

  defp fallback_room_inbox_id(%HumanUser{} = human, %XmtpRoom{} = room) do
    latest_presence_inbox_id(human, room) || latest_membership_inbox_id(human, room)
  end

  defp latest_presence_inbox_id(%HumanUser{} = human, %XmtpRoom{} = room) do
    XmtpPresence
    |> where(
      [presence],
      presence.room_id == ^room.id and presence.human_user_id == ^human.id and
        is_nil(presence.evicted_at)
    )
    |> order_by([presence], desc: presence.last_seen_at, desc: presence.id)
    |> limit(1)
    |> select([presence], presence.xmtp_inbox_id)
    |> Repo.one()
    |> normalize_inbox_id()
  end

  defp latest_membership_inbox_id(%HumanUser{} = human, %XmtpRoom{} = room) do
    XmtpMembershipCommand
    |> where([command], command.room_id == ^room.id and command.human_user_id == ^human.id)
    |> order_by([command], desc: command.inserted_at, desc: command.id)
    |> limit(1)
    |> select([command], command.xmtp_inbox_id)
    |> Repo.one()
    |> normalize_inbox_id()
  end

  defp normalize_inbox_id(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_inbox_id(_value), do: nil

  defp fetch_human(human_id) do
    case Repo.get(HumanUser, QueryHelpers.normalize_id(human_id)) do
      %HumanUser{} = human -> {:ok, human}
      nil -> {:error, :human_not_found}
    end
  end

  defp normalize_status(status) when is_binary(status), do: String.trim(status)
  defp normalize_status(status) when is_atom(status), do: Atom.to_string(status)
  defp normalize_status(_status), do: ""

  defp normalize_error_message(nil), do: "membership_command_failed"

  defp normalize_error_message(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "membership_command_failed"
      trimmed -> trimmed
    end
  end

  defp normalize_error_message(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_error_message(_value), do: "membership_command_failed"
end
