defmodule TechTree.XMTPMirror.Rooms do
  @moduledoc false

  import Ecto.Query

  alias TechTree.QueryHelpers
  alias TechTree.Repo
  alias TechTree.XMTPMirror.XmtpMembershipCommand
  alias TechTree.XMTPMirror.XmtpRoom

  @canonical_room_key "public-chatbox"
  @default_capacity 200
  @default_presence_ttl_seconds 120

  @spec canonical_room_key() :: String.t()
  def canonical_room_key, do: @canonical_room_key

  @spec default_capacity() :: pos_integer()
  def default_capacity, do: @default_capacity

  @spec default_presence_ttl_seconds() :: pos_integer()
  def default_presence_ttl_seconds, do: @default_presence_ttl_seconds

  @spec ensure_room(map()) :: {:ok, XmtpRoom.t()} | {:error, Ecto.Changeset.t()}
  def ensure_room(attrs) when is_map(attrs) do
    key = value_for(attrs, :room_key)

    case get_room_by_key(key) do
      nil ->
        %XmtpRoom{}
        |> XmtpRoom.changeset(normalize_room_attrs(attrs))
        |> Repo.insert()

      %XmtpRoom{} = room ->
        room
        |> XmtpRoom.changeset(normalize_room_attrs(attrs))
        |> Repo.update()
    end
  end

  @spec get_room_by_key(String.t() | nil) :: XmtpRoom.t() | nil
  def get_room_by_key(room_key) when is_binary(room_key) and room_key != "" do
    Repo.get_by(XmtpRoom, room_key: room_key)
  end

  def get_room_by_key(_room_key), do: nil

  @spec resolve_join_room(map()) :: {:ok, XmtpRoom.t()} | {:error, :room_not_found}
  def resolve_join_room(attrs) when is_map(attrs) do
    room =
      if explicit_room_reference?(attrs) do
        resolve_room(attrs)
      else
        select_join_room()
      end

    case room do
      nil -> {:error, :room_not_found}
      %XmtpRoom{} = resolved -> {:ok, resolved}
    end
  end

  @spec resolve_message_room(map()) :: {:ok, XmtpRoom.t()} | {:error, :room_not_found}
  def resolve_message_room(attrs) when is_map(attrs) do
    case resolve_room(attrs) do
      nil -> {:error, :room_not_found}
      %XmtpRoom{} = room -> {:ok, room}
    end
  end

  @spec resolve_room(map() | String.t() | integer() | nil) :: XmtpRoom.t() | nil
  def resolve_room(%{} = attrs) do
    cond do
      room_id = value_for(attrs, :room_id) ->
        Repo.get(XmtpRoom, QueryHelpers.normalize_id(room_id))

      shard_key = value_for(attrs, :shard_key) ->
        get_room_by_key(shard_key)

      room_key = value_for(attrs, :room_key) ->
        get_room_by_key(room_key)

      true ->
        get_room_by_key(@canonical_room_key)
    end
  end

  def resolve_room(room_key) when is_binary(room_key), do: get_room_by_key(room_key)
  def resolve_room(room_id) when is_integer(room_id), do: Repo.get(XmtpRoom, room_id)
  def resolve_room(_), do: nil

  @spec list_shards() :: [map()]
  def list_shards do
    XmtpRoom
    |> where([r], r.status == "active")
    |> order_by([r], asc: r.room_key)
    |> Repo.all()
    |> Enum.map(&encode_shard/1)
  end

  @spec active_member_count(integer()) :: non_neg_integer()
  def active_member_count(room_id) when is_integer(room_id) do
    add_count =
      XmtpMembershipCommand
      |> where([c], c.room_id == ^room_id and c.op == "add_member" and c.status == "done")
      |> Repo.aggregate(:count, :id)

    remove_count =
      XmtpMembershipCommand
      |> where([c], c.room_id == ^room_id and c.op == "remove_member" and c.status == "done")
      |> Repo.aggregate(:count, :id)

    max(add_count - remove_count, 0)
  end

  @spec value_for(map(), atom()) :: term()
  def value_for(attrs, key) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp explicit_room_reference?(attrs) when is_map(attrs) do
    not is_nil(value_for(attrs, :room_id)) or
      not is_nil(value_for(attrs, :shard_key)) or
      not is_nil(value_for(attrs, :room_key))
  end

  defp select_join_room do
    case list_joinable_rooms() do
      [room | _rest] -> room
      [] -> ensure_next_shard_room()
    end
  end

  defp list_joinable_rooms do
    XmtpRoom
    |> where([r], r.status == "active" and like(r.room_key, ^"#{@canonical_room_key}%"))
    |> Repo.all()
    |> Enum.sort_by(&room_sort_key/1)
    |> Enum.filter(&(active_member_count(&1.id) < @default_capacity))
  end

  defp ensure_next_shard_room do
    canonical_room = get_room_by_key(@canonical_room_key)

    if canonical_room do
      next_number =
        XmtpRoom
        |> where([r], like(r.room_key, ^"#{@canonical_room_key}-shard-%"))
        |> Repo.all()
        |> Enum.map(&room_sort_key/1)
        |> Enum.reject(&(&1 == 9_999))
        |> Enum.max(fn -> 1 end)
        |> Kernel.+(1)

      shard_key = "#{@canonical_room_key}-shard-#{next_number}"

      case ensure_room(%{
             room_key: shard_key,
             xmtp_group_id: "xmtp-#{shard_key}",
             name: "#{canonical_room.name || "Public Chatbox"} ##{next_number}",
             status: canonical_room.status || "active",
             presence_ttl_seconds:
               canonical_room.presence_ttl_seconds || @default_presence_ttl_seconds
           }) do
        {:ok, room} -> room
        {:error, _changeset} -> get_room_by_key(shard_key)
      end
    end
  end

  defp encode_shard(%XmtpRoom{} = room) do
    active_members = active_member_count(room.id)

    %{
      id: room.id,
      room_key: room.room_key,
      xmtp_group_id: room.xmtp_group_id,
      name: room.name,
      status: room.status,
      presence_ttl_seconds: room.presence_ttl_seconds,
      capacity: @default_capacity,
      active_members: active_members,
      joinable: active_members < @default_capacity
    }
  end

  defp normalize_room_attrs(attrs) do
    %{
      room_key: value_for(attrs, :room_key),
      xmtp_group_id: value_for(attrs, :xmtp_group_id),
      name: value_for(attrs, :name),
      status: value_for(attrs, :status) || "active",
      presence_ttl_seconds:
        value_for(attrs, :presence_ttl_seconds) || @default_presence_ttl_seconds
    }
  end

  defp room_sort_key(%XmtpRoom{room_key: @canonical_room_key}), do: 1

  defp room_sort_key(%XmtpRoom{room_key: room_key}) do
    room_key
    |> String.replace_prefix("#{@canonical_room_key}-shard-", "")
    |> Integer.parse()
    |> case do
      {shard_number, ""} when shard_number > 0 -> shard_number
      _ -> 9_999
    end
  end
end
