defmodule TechTree.XMTPMirror do
  @moduledoc false

  import Ecto.Query
  import TechTree.QueryHelpers

  alias TechTree.Accounts
  alias TechTree.Accounts.HumanUser
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Repo
  alias TechTree.XMTPMirror.{XmtpMembershipCommand, XmtpMessage, XmtpPresence, XmtpRoom}

  @canonical_room_key "public-trollbox"
  @canonical_room_name "Public Trollbox"
  @shard_room_prefix "public-trollbox-shard-"
  @shard_capacity 200
  @inflight_statuses ["pending", "processing"]
  @max_message_length 2_000
  @default_presence_ttl_seconds 120

  @type enqueue_result :: :queued | :already_pending | :already_applied

  @spec list_shards() :: [map()]
  def list_shards do
    rooms = active_rooms()
    member_counts = active_member_counts_by_room_ids(Enum.map(rooms, & &1.id))

    Enum.map(rooms, fn room ->
      encode_room_shard(room, Map.get(member_counts, room.id, 0))
    end)
  end

  @spec list_public_messages(map()) :: [XmtpMessage.t()]
  def list_public_messages(params) do
    limit = parse_limit(params, 100)
    room_key = room_key_from_params(params)

    XmtpMessage
    |> join(:inner, [m], r in XmtpRoom, on: r.id == m.room_id)
    |> join(:left, [m, _r], h in HumanUser, on: h.xmtp_inbox_id == m.sender_inbox_id)
    |> join(:left, [m, _r, _h], a in AgentIdentity,
      on: fragment("lower(?) = lower(?)", a.wallet_address, m.sender_wallet_address)
    )
    |> where([_m, r], r.room_key == ^room_key)
    |> where([m, _r, _h, _a], m.moderation_state != "hidden")
    |> where([m, _r, h, _a], m.sender_type != :human or is_nil(h.id) or h.role != "banned")
    |> where([m, _r, _h, a], m.sender_type != :agent or is_nil(a.id) or a.status == "active")
    |> order_by([m], desc: m.sent_at, desc: m.id)
    |> preload([_m, r], room: r)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec request_join(HumanUser.t(), map()) ::
          {:ok, map()} | {:error, :room_unavailable | :xmtp_inbox_already_bound | Ecto.Changeset.t()}
  def request_join(human, attrs \\ %{}) do
    requested_room_key = explicit_room_key_from_params(attrs)

    with {:ok, refreshed_human} <- maybe_assign_inbox_id(human, attrs),
         {:ok, room} <- resolve_join_room(requested_room_key) do
      room_key = room.room_key

      case enqueue_membership_op(refreshed_human, room_key, "add_member") do
        {:ok, :queued} ->
          {:ok, join_status_payload("pending", refreshed_human.id, room_key, room)}

        {:ok, :already_pending} ->
          {:ok, join_status_payload("pending", refreshed_human.id, room_key, room)}

        {:ok, :already_applied} ->
          {:ok, join_status_payload("joined", refreshed_human.id, room_key, room)}

        {:error, :room_unavailable} ->
          {:ok, join_status_payload("room_unavailable", refreshed_human.id, room_key, room)}

        {:error, :missing_inbox_id} ->
          {:ok, join_status_payload("missing_inbox_id", refreshed_human.id, room_key, room)}
      end
    end
  end

  @spec request_leave(HumanUser.t(), map()) ::
          {:ok, map()} | {:error, :room_unavailable | :xmtp_inbox_already_bound | Ecto.Changeset.t()}
  def request_leave(human, attrs \\ %{}) do
    requested_room_key = explicit_room_key_from_params(attrs)

    with {:ok, refreshed_human} <- maybe_assign_inbox_id(human, attrs),
         {:ok, room} <- resolve_leave_room(refreshed_human, requested_room_key) do
      room_key = room.room_key

      case enqueue_membership_op(refreshed_human, room_key, "remove_member") do
        {:ok, :queued} ->
          {:ok, join_status_payload("pending", refreshed_human.id, room_key, room)}

        {:ok, :already_pending} ->
          {:ok, join_status_payload("pending", refreshed_human.id, room_key, room)}

        {:ok, :already_applied} ->
          {:ok, join_status_payload("left", refreshed_human.id, room_key, room)}

        {:error, :room_unavailable} ->
          {:ok, join_status_payload("room_unavailable", refreshed_human.id, room_key, room)}

        {:error, :missing_inbox_id} ->
          {:ok, join_status_payload("missing_inbox_id", refreshed_human.id, room_key, room)}
      end
    end
  end

  @spec heartbeat_presence(HumanUser.t(), map()) ::
          {:ok, map()}
          | {:error,
             :room_unavailable
             | :missing_inbox_id
             | :membership_required
             | :xmtp_inbox_already_bound
             | Ecto.Changeset.t()}
  def heartbeat_presence(human, attrs \\ %{}) do
    requested_room_key = explicit_room_key_from_params(attrs)

    with {:ok, refreshed_human} <- maybe_assign_inbox_id(human, attrs),
         {:ok, room} <- resolve_presence_room(refreshed_human, requested_room_key),
         room_key = room.room_key,
         :ok <- ensure_joined_membership(refreshed_human, room),
         {:ok, {observed_at, expires_at, evicted_count}} <-
           refresh_presence_state(refreshed_human, room) do
      {:ok,
       %{
         status: "alive",
         human_id: refreshed_human.id,
         room_key: room_key,
         shard_key: room_key,
         xmtp_group_id: room.xmtp_group_id,
         observed_at: observed_at,
         expires_at: expires_at,
         ttl_seconds: presence_ttl_seconds(room),
         eviction_enqueued: evicted_count
       }}
    end
  end

  @spec create_human_message(HumanUser.t(), map()) ::
          {:ok, XmtpMessage.t()}
          | {:error,
             :room_unavailable
             | :missing_inbox_id
             | :membership_required
             | :body_required
             | :body_too_long
             | :invalid_reply_to_message
             | :invalid_reactions
             | :xmtp_inbox_already_bound
             | Ecto.Changeset.t()}
  def create_human_message(human, attrs) when is_map(attrs) do
    room_key = room_key_from_params(attrs)

    with {:ok, body} <- normalize_message_body(attrs),
         {:ok, refreshed_human} <- maybe_assign_inbox_id(human, attrs),
         {:ok, room} <- fetch_active_room(room_key),
         :ok <- ensure_joined_membership(refreshed_human, room),
         {:ok, message} <- insert_human_message(room, refreshed_human, body, attrs) do
      {:ok, message}
    end
  end

  @spec membership_for(HumanUser.t(), map()) :: map()
  def membership_for(human, attrs \\ %{}) do
    room_key = room_key_from_params(attrs)

    case fetch_active_room(room_key) do
      {:ok, room} ->
        case normalized_inbox_id(human.xmtp_inbox_id) do
          nil ->
            %{
              human_id: human.id,
              room_key: room_key,
              shard_key: room_key,
              xmtp_group_id: room.xmtp_group_id,
              room_present: true,
              state: "missing_inbox_id"
            }

          inbox_id ->
            %{
              human_id: human.id,
              room_key: room_key,
              shard_key: room_key,
              xmtp_group_id: room.xmtp_group_id,
              room_present: true,
              state:
                room.id
                |> latest_membership_command(human.id, inbox_id)
                |> membership_state_from_command()
            }
        end

      {:error, :room_unavailable} ->
        %{
          human_id: human.id,
          room_key: room_key,
          shard_key: room_key,
          xmtp_group_id: nil,
          room_present: false,
          state: "room_unavailable"
        }
    end
  end

  @spec get_room_by_key(String.t()) :: XmtpRoom.t() | nil
  def get_room_by_key(room_key), do: Repo.get_by(XmtpRoom, room_key: room_key)

  @spec react_to_message(HumanUser.t(), integer() | String.t(), map()) ::
          {:ok, XmtpMessage.t()}
          | {:error,
             :xmtp_inbox_already_bound
             | :message_not_found
             | :membership_required
             | :invalid_reaction_emoji
             | :invalid_reaction_operation
             | Ecto.Changeset.t()}
  def react_to_message(%HumanUser{} = human, message_id, attrs) when is_map(attrs) do
    with {:ok, refreshed_human} <- maybe_assign_inbox_id(human, attrs),
         {:ok, room_message} <- fetch_message_for_reaction(message_id),
         :ok <- ensure_joined_membership(refreshed_human, room_message.room),
         {:ok, emoji} <- normalize_reaction_emoji(attrs),
         {:ok, operation} <- normalize_reaction_operation(attrs),
         {:ok, updated} <- update_message_reactions(room_message.id, emoji, operation) do
      {:ok, updated}
    end
  end

  @spec ensure_room(map()) :: {:ok, XmtpRoom.t()} | {:error, Ecto.Changeset.t()}
  def ensure_room(attrs) do
    normalized_attrs =
      attrs
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    room =
      Repo.get_by(
        XmtpRoom,
        room_key: normalized_attrs["room_key"] || normalized_attrs[:room_key]
      ) || %XmtpRoom{}

    room |> XmtpRoom.changeset(normalized_attrs) |> Repo.insert_or_update()
  end

  @spec ingest_message(map()) ::
          {:ok, XmtpMessage.t()}
          | {:error, :invalid_reply_to_message | :invalid_reactions | Ecto.Changeset.t()}
  def ingest_message(attrs) do
    room_id = attrs["room_id"] || attrs[:room_id]

    with {:ok, reply_to_message_id} <- resolve_reply_to_message_id(attrs, room_id),
         {:ok, reactions} <- normalize_reactions(attrs["reactions"] || attrs[:reactions]) do
      normalized_attrs =
        attrs
        |> Map.put(:reply_to_message_id, reply_to_message_id)
        |> Map.put(:reactions, reactions)

      message =
        Repo.get_by(XmtpMessage,
          xmtp_message_id: attrs["xmtp_message_id"] || attrs[:xmtp_message_id]
        ) || %XmtpMessage{}

      message |> XmtpMessage.changeset(normalized_attrs) |> Repo.insert_or_update()
    end
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

  @spec resolve_command(integer() | String.t(), map()) ::
          :ok | {:error, :invalid_resolution_status}
  def resolve_command(id, attrs) when is_map(attrs) do
    resolution =
      attrs
      |> Map.get("status", Map.get(attrs, :status))
      |> normalize_resolution_status()

    case resolution do
      {:ok, "done"} ->
        do_resolve_command(id, %{status: "done"})

      {:ok, "failed"} ->
        do_resolve_command(id, %{
          status: "failed",
          error:
            attrs
            |> Map.get("error", Map.get(attrs, :error))
            |> normalize_command_error()
        })

      :error ->
        {:error, :invalid_resolution_status}
    end
  end

  def resolve_command(_id, _attrs), do: {:error, :invalid_resolution_status}

  @spec do_resolve_command(integer() | String.t(), map()) :: :ok
  defp do_resolve_command(id, attrs) do
    command = Repo.get!(XmtpMembershipCommand, normalize_id(id))
    command |> XmtpMembershipCommand.resolve_changeset(attrs) |> Repo.update!()
    :ok
  end

  @spec add_human_to_canonical_room(integer() | String.t()) :: :ok
  def add_human_to_canonical_room(human_id) do
    human = Repo.get!(HumanUser, normalize_id(human_id))

    case enqueue_membership_op(human, @canonical_room_key, "add_member") do
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

    case enqueue_membership_op(human, @canonical_room_key, "remove_member") do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "cannot enqueue remove_member for human_user_id=#{human.id}: #{inspect(reason)}"
    end
  end

  @spec normalize_resolution_status(String.t() | nil) :: {:ok, String.t()} | :error
  defp normalize_resolution_status(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "done" -> {:ok, "done"}
      "failed" -> {:ok, "failed"}
      _ -> :error
    end
  end

  defp normalize_resolution_status(_value), do: :error

  @spec normalize_command_error(String.t() | nil) :: String.t()
  defp normalize_command_error(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> "membership_command_failed"
      normalized -> normalized
    end
  end

  defp normalize_command_error(_value), do: "membership_command_failed"

  @spec room_key_from_params(map() | nil) :: String.t()
  defp room_key_from_params(params) when is_map(params) do
    params
    |> Map.get(
      "room_key",
      Map.get(params, :room_key, Map.get(params, "shard_key", Map.get(params, :shard_key)))
    )
    |> normalize_room_key()
  end

  defp room_key_from_params(_params), do: @canonical_room_key

  @spec explicit_room_key_from_params(map() | nil) :: String.t() | nil
  defp explicit_room_key_from_params(params) when is_map(params) do
    params
    |> Map.get(
      "room_key",
      Map.get(params, :room_key, Map.get(params, "shard_key", Map.get(params, :shard_key)))
    )
    |> case do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          normalized -> normalized
        end

      _ ->
        nil
    end
  end

  defp explicit_room_key_from_params(_params), do: nil

  @spec normalize_room_key(term()) :: String.t()
  defp normalize_room_key(value) when is_binary(value) do
    case String.trim(value) do
      "" -> @canonical_room_key
      normalized -> normalized
    end
  end

  defp normalize_room_key(_value), do: @canonical_room_key

  @spec active_rooms() :: [XmtpRoom.t()]
  defp active_rooms do
    XmtpRoom
    |> where([room], room.status == "active")
    |> order_by([room], asc: room.room_key, asc: room.id)
    |> Repo.all()
  end

  @spec active_member_counts_by_room_ids([integer()]) :: %{optional(integer()) => non_neg_integer()}
  defp active_member_counts_by_room_ids([]), do: %{}

  defp active_member_counts_by_room_ids(room_ids) when is_list(room_ids) do
    latest_per_room_inbox_query =
      XmtpMembershipCommand
      |> where([c], c.room_id in ^room_ids and c.status == "done")
      |> order_by([c], asc: c.room_id, asc: c.xmtp_inbox_id, desc: c.inserted_at, desc: c.id)
      |> distinct([c], [c.room_id, c.xmtp_inbox_id])
      |> select([c], %{room_id: c.room_id, op: c.op})

    from(
      row in subquery(latest_per_room_inbox_query),
      where: row.op == "add_member",
      group_by: row.room_id,
      select: {row.room_id, count()}
    )
    |> Repo.all()
    |> Map.new()
  end

  @spec room_joinable?(XmtpRoom.t(), map()) :: boolean()
  defp room_joinable?(%XmtpRoom{} = room, member_counts) do
    Map.get(member_counts, room.id, 0) < @shard_capacity
  end

  @spec resolve_join_room(String.t() | nil) :: {:ok, XmtpRoom.t()} | {:error, :room_unavailable}
  defp resolve_join_room(requested_room_key) do
    with {:ok, _canonical} <- ensure_canonical_room_exists() do
      current_rooms = active_rooms()
      member_counts = active_member_counts_by_room_ids(Enum.map(current_rooms, & &1.id))

      room =
        case requested_room_key do
          nil ->
            first_joinable_shard_room(member_counts) || maybe_create_next_shard_room()

          room_key ->
            case fetch_active_room(room_key) do
              {:ok, requested_room} ->
                if room_joinable?(requested_room, member_counts) do
                  requested_room
                else
                  first_joinable_shard_room(member_counts) || maybe_create_next_shard_room()
                end

              _ ->
                first_joinable_shard_room(member_counts) || maybe_create_next_shard_room()
            end
        end

      case room do
        %XmtpRoom{} = resolved -> {:ok, resolved}
        _ -> {:error, :room_unavailable}
      end
    end
  end

  @spec resolve_leave_room(HumanUser.t(), String.t() | nil) ::
          {:ok, XmtpRoom.t()} | {:error, :room_unavailable}
  defp resolve_leave_room(%HumanUser{} = human, requested_room_key) do
    case requested_room_key do
      nil ->
        case joined_room_for_human(human) do
          %XmtpRoom{} = room ->
            {:ok, room}

          nil ->
            case fetch_active_room(@canonical_room_key) do
              {:ok, room} -> {:ok, room}
              _ -> {:error, :room_unavailable}
            end
        end

      room_key ->
        fetch_active_room(room_key)
    end
  end

  @spec resolve_presence_room(HumanUser.t(), String.t() | nil) ::
          {:ok, XmtpRoom.t()} | {:error, :room_unavailable}
  defp resolve_presence_room(%HumanUser{} = human, requested_room_key) do
    case requested_room_key do
      nil ->
        case joined_room_for_human(human) do
          %XmtpRoom{} = room -> {:ok, room}
          nil -> fetch_active_room(@canonical_room_key)
        end

      room_key ->
        fetch_active_room(room_key)
    end
  end

  @spec first_joinable_shard_room(map()) :: XmtpRoom.t() | nil
  defp first_joinable_shard_room(member_counts) when is_map(member_counts) do
    active_rooms()
    |> Enum.sort_by(fn room -> {shard_index(room.room_key), room.room_key, room.id} end)
    |> Enum.find(fn room -> room_joinable?(room, member_counts) end)
  end

  @spec maybe_create_next_shard_room() :: XmtpRoom.t() | nil
  defp maybe_create_next_shard_room do
    next_index =
      active_rooms()
      |> Enum.map(&shard_index(&1.room_key))
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)

    room_key = shard_key_for_index(next_index)

    attrs = %{
      room_key: room_key,
      xmtp_group_id: "xmtp-#{room_key}-#{System.unique_integer([:positive, :monotonic])}",
      name: shard_name(next_index),
      status: "active",
      presence_ttl_seconds: @default_presence_ttl_seconds
    }

    case ensure_room(attrs) do
      {:ok, room} -> room
      {:error, _changeset} -> Repo.get_by(XmtpRoom, room_key: room_key)
    end
  end

  @spec ensure_canonical_room_exists() :: {:ok, XmtpRoom.t()} | {:error, :room_unavailable}
  defp ensure_canonical_room_exists do
    case fetch_active_room(@canonical_room_key) do
      {:ok, room} ->
        {:ok, room}

      {:error, :room_unavailable} ->
        attrs = %{
          room_key: @canonical_room_key,
          xmtp_group_id:
            "xmtp-#{@canonical_room_key}-#{System.unique_integer([:positive, :monotonic])}",
          name: @canonical_room_name,
          status: "active",
          presence_ttl_seconds: @default_presence_ttl_seconds
        }

        case ensure_room(attrs) do
          {:ok, room} -> {:ok, room}
          {:error, _} -> {:error, :room_unavailable}
        end
    end
  end

  @spec shard_index(String.t() | nil) :: non_neg_integer()
  defp shard_index(@canonical_room_key), do: 1

  defp shard_index(room_key) when is_binary(room_key) do
    case Regex.run(~r/^public-trollbox-shard-(\d+)$/, room_key, capture: :all_but_first) do
      [value] ->
        case Integer.parse(value) do
          {idx, ""} when idx > 1 -> idx
          _ -> 1
        end

      _ ->
        1
    end
  end

  defp shard_index(_room_key), do: 1

  @spec shard_key_for_index(pos_integer()) :: String.t()
  defp shard_key_for_index(1), do: @canonical_room_key
  defp shard_key_for_index(index), do: "#{@shard_room_prefix}#{index}"

  @spec shard_name(pos_integer()) :: String.t()
  defp shard_name(1), do: @canonical_room_name
  defp shard_name(index), do: "#{@canonical_room_name} ##{index}"

  @spec joined_room_for_human(HumanUser.t()) :: XmtpRoom.t() | nil
  defp joined_room_for_human(%HumanUser{} = human) do
    inbox_id = normalized_inbox_id(human.xmtp_inbox_id)

    if is_nil(inbox_id) do
      nil
    else
      active_rooms()
      |> Enum.find(fn room ->
        case latest_membership_command(room.id, human.id, inbox_id) do
          %XmtpMembershipCommand{op: "add_member", status: "done"} -> true
          _ -> false
        end
      end)
    end
  end

  @spec fetch_message_for_reaction(integer() | String.t()) ::
          {:ok, XmtpMessage.t()} | {:error, :message_not_found}
  defp fetch_message_for_reaction(message_id) do
    normalized_id =
      case message_id do
        value when is_integer(value) ->
          {:ok, value}

        value when is_binary(value) ->
          case Integer.parse(String.trim(value)) do
            {parsed, ""} when parsed > 0 -> {:ok, parsed}
            _ -> :error
          end

        _ ->
          :error
      end

    case normalized_id do
      {:ok, id} ->
        case Repo.get(XmtpMessage, id) |> Repo.preload(:room) do
          %XmtpMessage{room: %XmtpRoom{status: "active"}} = message -> {:ok, message}
          _ -> {:error, :message_not_found}
        end

      :error ->
        {:error, :message_not_found}
    end
  end

  @spec normalize_reaction_emoji(map()) :: {:ok, String.t()} | {:error, :invalid_reaction_emoji}
  defp normalize_reaction_emoji(attrs) do
    attrs
    |> Map.get(
      "emoji",
      Map.get(attrs, :emoji, Map.get(attrs, "reaction", Map.get(attrs, :reaction)))
    )
    |> case do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, :invalid_reaction_emoji}
          normalized when byte_size(normalized) > 32 -> {:error, :invalid_reaction_emoji}
          normalized -> {:ok, normalized}
        end

      _ ->
        {:error, :invalid_reaction_emoji}
    end
  end

  @spec normalize_reaction_operation(map()) ::
          {:ok, :add | :remove} | {:error, :invalid_reaction_operation}
  defp normalize_reaction_operation(attrs) do
    attrs
    |> Map.get(
      "op",
      Map.get(attrs, :op, Map.get(attrs, "action", Map.get(attrs, :action, "add")))
    )
    |> case do
      value when is_binary(value) ->
        case String.trim(value) |> String.downcase() do
          "add" -> {:ok, :add}
          "remove" -> {:ok, :remove}
          _ -> {:error, :invalid_reaction_operation}
        end

      _ ->
        {:error, :invalid_reaction_operation}
    end
  end

  @spec update_message_reactions(integer(), String.t(), :add | :remove) ::
          {:ok, XmtpMessage.t()} | {:error, Ecto.Changeset.t()}
  defp update_message_reactions(message_id, emoji, operation) do
    Repo.transaction(fn ->
      message =
        XmtpMessage
        |> where([m], m.id == ^message_id)
        |> lock("FOR UPDATE")
        |> limit(1)
        |> Repo.one!()

      existing_reactions = message.reactions || %{}
      current_count = Map.get(existing_reactions, emoji, 0)

      next_count =
        case operation do
          :add -> current_count + 1
          :remove -> max(current_count - 1, 0)
        end

      updated_reactions =
        if next_count == 0,
          do: Map.delete(existing_reactions, emoji),
          else: Map.put(existing_reactions, emoji, next_count)

      message
      |> Ecto.Changeset.change(reactions: updated_reactions)
      |> Repo.update!()
      |> Repo.preload(:room)
    end)
  rescue
    Ecto.NoResultsError -> {:error, :message_not_found}
  end

  @spec enqueue_membership_op(HumanUser.t(), String.t(), String.t()) ::
          {:ok, enqueue_result()} | {:error, :room_unavailable | :missing_inbox_id}
  defp enqueue_membership_op(human, room_key, op) do
    case fetch_active_room(room_key) do
      {:ok, %XmtpRoom{id: room_id}} ->
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

      {:error, :room_unavailable} ->
        {:error, :room_unavailable}
    end
  end

  @spec encode_room_shard(XmtpRoom.t(), non_neg_integer()) :: map()
  defp encode_room_shard(%XmtpRoom{} = room, active_members) do
    %{
      room_key: room.room_key,
      shard_key: room.room_key,
      xmtp_group_id: room.xmtp_group_id,
      name: room.name,
      status: room.status,
      presence_ttl_seconds: presence_ttl_seconds(room),
      active_members: active_members,
      capacity: @shard_capacity,
      joinable: active_members < @shard_capacity
    }
  end

  @spec join_status_payload(String.t(), integer(), String.t(), XmtpRoom.t() | nil) :: map()
  defp join_status_payload(status, human_id, room_key, room) do
    ttl_seconds =
      case room do
        %XmtpRoom{} = loaded_room -> presence_ttl_seconds(loaded_room)
        _ -> @default_presence_ttl_seconds
      end

    %{
      status: status,
      human_id: human_id,
      room_key: room_key,
      shard_key: room_key,
      xmtp_group_id: if(is_nil(room), do: nil, else: room.xmtp_group_id),
      presence_ttl_seconds: ttl_seconds
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

  @spec fetch_active_room(String.t()) :: {:ok, XmtpRoom.t()} | {:error, :room_unavailable}
  defp fetch_active_room(room_key) do
    case Repo.get_by(XmtpRoom, room_key: room_key) do
      %XmtpRoom{status: "active"} = room -> {:ok, room}
      _ -> {:error, :room_unavailable}
    end
  end

  @spec ensure_joined_membership(HumanUser.t(), XmtpRoom.t()) ::
          :ok | {:error, :membership_required | :missing_inbox_id}
  defp ensure_joined_membership(%HumanUser{} = human, %XmtpRoom{} = room) do
    case normalized_inbox_id(human.xmtp_inbox_id) do
      nil ->
        {:error, :missing_inbox_id}

      inbox_id ->
        case latest_membership_command(room.id, human.id, inbox_id) |> membership_state_from_command() do
          "joined" -> :ok
          _ -> {:error, :membership_required}
        end
    end
  end

  @spec normalize_message_body(map()) ::
          {:ok, String.t()} | {:error, :body_required | :body_too_long}
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

  @spec refresh_presence_state(HumanUser.t(), XmtpRoom.t()) ::
          {:ok, {DateTime.t(), DateTime.t(), non_neg_integer()}} | {:error, Ecto.Changeset.t()}
  defp refresh_presence_state(%HumanUser{} = human, %XmtpRoom{} = room) do
    observed_at = DateTime.utc_now()
    ttl_seconds = presence_ttl_seconds(room)
    expires_at = DateTime.add(observed_at, ttl_seconds, :second)

    with {:ok, _presence} <- upsert_presence_heartbeat(human, room, observed_at, expires_at),
         {:ok, evicted_count} <- enqueue_expired_presence_evictions(room, observed_at) do
      {:ok, {observed_at, expires_at, evicted_count}}
    end
  end

  @spec upsert_presence_heartbeat(HumanUser.t(), XmtpRoom.t(), DateTime.t(), DateTime.t()) ::
          {:ok, XmtpPresence.t()} | {:error, Ecto.Changeset.t()}
  defp upsert_presence_heartbeat(
         %HumanUser{} = human,
         %XmtpRoom{} = room,
         observed_at,
         expires_at
       ) do
    attrs = %{
      room_id: room.id,
      human_user_id: human.id,
      xmtp_inbox_id: human.xmtp_inbox_id,
      last_seen_at: observed_at,
      expires_at: expires_at,
      evicted_at: nil
    }

    existing =
      Repo.get_by(XmtpPresence, room_id: room.id, xmtp_inbox_id: human.xmtp_inbox_id) ||
        %XmtpPresence{}

    existing
    |> XmtpPresence.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @spec enqueue_expired_presence_evictions(XmtpRoom.t(), DateTime.t()) ::
          {:ok, non_neg_integer()} | {:error, Ecto.Changeset.t()}
  defp enqueue_expired_presence_evictions(%XmtpRoom{} = room, observed_at) do
    Repo.transaction(fn ->
      XmtpPresence
      |> where(
        [presence],
        presence.room_id == ^room.id and is_nil(presence.evicted_at) and
          presence.expires_at < ^observed_at
      )
      |> order_by([presence], asc: presence.expires_at, asc: presence.id)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> Repo.all()
      |> Enum.reduce(0, fn presence, acc ->
        queued? =
          maybe_enqueue_stale_leave(room.id, presence.human_user_id, presence.xmtp_inbox_id)

        presence
        |> Ecto.Changeset.change(evicted_at: observed_at)
        |> Repo.update!()

        if queued?, do: acc + 1, else: acc
      end)
    end)
  end

  @spec maybe_enqueue_stale_leave(integer(), integer(), String.t()) :: boolean()
  defp maybe_enqueue_stale_leave(room_id, human_user_id, inbox_id) do
    cond do
      inflight_command(room_id, human_user_id, inbox_id, "remove_member") != nil ->
        false

      operation_already_applied?(room_id, human_user_id, inbox_id, "remove_member") ->
        false

      true ->
        enqueue_membership_command!(room_id, human_user_id, inbox_id, "remove_member")
        true
    end
  end

  @spec insert_human_message(XmtpRoom.t(), HumanUser.t(), String.t(), map()) ::
          {:ok, XmtpMessage.t()}
          | {:error, :invalid_reply_to_message | :invalid_reactions | Ecto.Changeset.t()}
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

    with {:ok, reply_to_message_id} <- resolve_reply_to_message_id(attrs, room.id),
         {:ok, reactions} <- normalize_reactions(attrs["reactions"] || attrs[:reactions]) do
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
        moderation_state: "visible",
        reply_to_message_id: reply_to_message_id,
        reactions: reactions
      }

      %XmtpMessage{}
      |> XmtpMessage.changeset(payload)
      |> Repo.insert()
    end
  end

  @spec resolve_reply_to_message_id(map(), integer() | String.t() | nil) ::
          {:ok, integer() | nil} | {:error, :invalid_reply_to_message}
  defp resolve_reply_to_message_id(attrs, room_id) do
    reply_value = Map.get(attrs, "reply_to_message_id", Map.get(attrs, :reply_to_message_id))

    cond do
      is_nil(reply_value) ->
        {:ok, nil}

      room_id == nil ->
        {:error, :invalid_reply_to_message}

      true ->
        normalize_reply_to_message_id(reply_value, normalize_id(room_id))
    end
  rescue
    _ -> {:error, :invalid_reply_to_message}
  end

  @spec normalize_reply_to_message_id(term(), integer()) ::
          {:ok, integer() | nil} | {:error, :invalid_reply_to_message}
  defp normalize_reply_to_message_id(value, room_id) when is_integer(value) do
    validate_reply_to_message_id(value, room_id)
  end

  defp normalize_reply_to_message_id(value, room_id) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        {:ok, nil}

      true ->
        case Integer.parse(trimmed) do
          {parsed_id, ""} ->
            validate_reply_to_message_id(parsed_id, room_id)

          _ ->
            case Repo.get_by(XmtpMessage, room_id: room_id, xmtp_message_id: trimmed) do
              %XmtpMessage{id: id} -> {:ok, id}
              _ -> {:error, :invalid_reply_to_message}
            end
        end
    end
  end

  defp normalize_reply_to_message_id(_value, _room_id), do: {:error, :invalid_reply_to_message}

  @spec validate_reply_to_message_id(integer(), integer()) ::
          {:ok, integer()} | {:error, :invalid_reply_to_message}
  defp validate_reply_to_message_id(value, room_id) when value > 0 do
    case Repo.get(XmtpMessage, value) do
      %XmtpMessage{room_id: ^room_id} -> {:ok, value}
      _ -> {:error, :invalid_reply_to_message}
    end
  end

  defp validate_reply_to_message_id(_value, _room_id), do: {:error, :invalid_reply_to_message}

  @spec normalize_reactions(term()) :: {:ok, map()} | {:error, :invalid_reactions}
  defp normalize_reactions(nil), do: {:ok, %{}}

  defp normalize_reactions(value) when is_map(value) do
    value
    |> Enum.reduce_while(%{}, fn {raw_key, raw_value}, acc ->
      with {:ok, key} <- normalize_reaction_key(raw_key),
           {:ok, count} <- normalize_reaction_count(raw_value) do
        {:cont, Map.put(acc, key, count)}
      else
        _ -> {:halt, :error}
      end
    end)
    |> case do
      :error -> {:error, :invalid_reactions}
      reactions -> {:ok, reactions}
    end
  end

  defp normalize_reactions(_value), do: {:error, :invalid_reactions}

  @spec normalize_reaction_key(term()) :: {:ok, String.t()} | :error
  defp normalize_reaction_key(key) when is_binary(key) do
    case String.trim(key) do
      "" -> :error
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_reaction_key(_key), do: :error

  @spec normalize_reaction_count(term()) :: {:ok, non_neg_integer()} | :error
  defp normalize_reaction_count(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp normalize_reaction_count(value) when is_float(value) and value >= 0,
    do: {:ok, trunc(value)}

  defp normalize_reaction_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {count, ""} when count >= 0 -> {:ok, count}
      _ -> :error
    end
  end

  defp normalize_reaction_count(_value), do: :error

  @spec presence_ttl_seconds(XmtpRoom.t()) :: integer()
  defp presence_ttl_seconds(%XmtpRoom{presence_ttl_seconds: ttl})
       when is_integer(ttl) and ttl > 0,
       do: ttl

  defp presence_ttl_seconds(_room), do: @default_presence_ttl_seconds

  @spec lock_human!(integer()) :: HumanUser.t()
  defp lock_human!(human_id) do
    HumanUser
    |> where([h], h.id == ^human_id)
    |> lock("FOR UPDATE")
    |> limit(1)
    |> Repo.one!()
  end

  @spec inflight_command(integer(), integer(), String.t(), String.t()) ::
          XmtpMembershipCommand.t() | nil
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

  @spec latest_membership_command(integer(), integer(), String.t()) ::
          XmtpMembershipCommand.t() | nil
  defp latest_membership_command(room_id, human_id, inbox_id) do
    XmtpMembershipCommand
    |> where(
      [c],
      c.room_id == ^room_id and c.human_user_id == ^human_id and c.xmtp_inbox_id == ^inbox_id
    )
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

  @spec enqueue_membership_command!(integer(), integer(), String.t(), String.t()) ::
          XmtpMembershipCommand.t()
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

  defp membership_state_from_command(%XmtpMembershipCommand{op: "add_member", status: "done"}),
    do: "joined"

  defp membership_state_from_command(%XmtpMembershipCommand{op: "add_member", status: "failed"}),
    do: "join_failed"

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
