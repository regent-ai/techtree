defmodule TechTree.Watches do
  @moduledoc false

  import Ecto.Query
  import TechTree.QueryHelpers

  require Logger

  alias Phoenix.PubSub
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Repo
  alias TechTree.Watches.NodeWatcher

  @online_session_ttl_seconds 120
  @cache_prefix "techtree:watches:v1"
  @fanout_telemetry_event [:tech_tree, :watches, :fanout]

  @spec watch_human(integer() | String.t(), integer()) ::
          {:ok, NodeWatcher.t()} | {:error, Ecto.Changeset.t()}
  def watch_human(node_id, human_id) do
    create_watch(node_id, :human, human_id)
  end

  @spec unwatch_human(integer() | String.t(), integer()) :: :ok
  def unwatch_human(node_id, human_id) do
    delete_watch(node_id, :human, human_id)
  end

  @spec watch_agent(integer() | String.t(), integer()) ::
          {:ok, NodeWatcher.t()} | {:error, Ecto.Changeset.t()}
  def watch_agent(node_id, agent_id) do
    create_watch(node_id, :agent, agent_id)
  end

  @spec unwatch_agent(integer() | String.t(), integer()) :: :ok
  def unwatch_agent(node_id, agent_id) do
    delete_watch(node_id, :agent, agent_id)
  end

  @spec list_agent_watches(integer(), map()) :: [NodeWatcher.t()]
  def list_agent_watches(agent_id, params \\ %{}) when is_integer(agent_id) and agent_id > 0 do
    limit = parse_limit(params, 50)
    cursor = parse_cursor(params)

    NodeWatcher
    |> where([w], w.watcher_type == :agent and w.watcher_ref == ^agent_id)
    |> maybe_before_cursor(cursor)
    |> order_by([w], desc: w.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec add_online_session(integer() | String.t(), integer() | String.t()) :: :ok
  def add_online_session(node_id, session_id) do
    normalized_node_id = normalize_id(node_id)
    normalized_session_id = normalize_session_id(session_id)

    if normalized_session_id == "" do
      :ok
    else
      key = online_sessions_key(normalized_node_id)
      session_ref = online_session_ref(normalized_session_id)

      case TechTree.LocalCache.set_add(key, session_ref, @online_session_ttl_seconds) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.debug(
            "local cache online-session add failed node_id=#{normalized_node_id} session_ref=#{session_ref}: #{inspect(reason)}"
          )

          :ok
      end
    end
  end

  @spec remove_online_session(integer() | String.t(), integer() | String.t()) :: :ok
  def remove_online_session(node_id, session_id) do
    normalized_node_id = normalize_id(node_id)
    normalized_session_id = normalize_session_id(session_id)

    if normalized_session_id == "" do
      :ok
    else
      key = online_sessions_key(normalized_node_id)
      session_ref = online_session_ref(normalized_session_id)

      case TechTree.LocalCache.set_remove(key, session_ref, @online_session_ttl_seconds) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.debug(
            "local cache online-session remove failed node_id=#{normalized_node_id} session_ref=#{session_ref}: #{inspect(reason)}"
          )

          :ok
      end
    end
  end

  @spec list_online_sessions(integer() | String.t()) :: [String.t()]
  def list_online_sessions(node_id) do
    normalized_node_id = normalize_id(node_id)
    key = online_sessions_key(normalized_node_id)

    case TechTree.LocalCache.set_members(key) do
      {:ok, session_ids} when is_list(session_ids) ->
        session_ids
        |> Enum.map(&normalize_session_id/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()
        |> Enum.sort()

      {:error, reason} ->
        Logger.debug(
          "local cache online-session list failed node_id=#{normalized_node_id}: #{inspect(reason)}"
        )

        []
    end
  end

  @spec fanout_node_activity(integer() | String.t()) :: :ok
  def fanout_node_activity(node_id) do
    normalized_node_id = normalize_id(node_id)
    online_session_ids = list_online_sessions(normalized_node_id)

    watchers =
      NodeWatcher
      |> where([w], w.node_id == ^normalized_node_id)
      |> order_by([w], asc: w.id)
      |> select([w], {w.watcher_type, w.watcher_ref})
      |> Repo.all()

    {watcher_broadcasts, session_broadcasts} =
      Enum.reduce(watchers, {0, 0}, fn {watcher_type, watcher_ref}, {watcher_acc, session_acc} ->
        payload = build_fanout_payload(normalized_node_id, watcher_type, watcher_ref)

        PubSub.broadcast(
          TechTree.PubSub,
          watcher_node_topic(watcher_type, watcher_ref, normalized_node_id),
          payload
        )

        session_count =
          Enum.reduce(online_session_ids, 0, fn session_id, count ->
            PubSub.broadcast(TechTree.PubSub, online_session_topic(session_id), payload)
            count + 1
          end)

        {watcher_acc + 1, session_acc + session_count}
      end)

    measurements = %{
      watchers: length(watchers),
      online_sessions: length(online_session_ids),
      watcher_broadcasts: watcher_broadcasts,
      session_broadcasts: session_broadcasts
    }

    metadata = %{
      node_id: normalized_node_id,
      outcome: "ok"
    }

    :telemetry.execute(@fanout_telemetry_event, measurements, metadata)

    Logger.debug(
      "watch fanout node_id=#{normalized_node_id} watchers=#{measurements.watchers} online_sessions=#{measurements.online_sessions} watcher_broadcasts=#{watcher_broadcasts} session_broadcasts=#{session_broadcasts}"
    )

    :ok
  end

  @spec create_watch(integer() | String.t(), atom(), integer()) ::
          {:ok, NodeWatcher.t()} | {:error, Ecto.Changeset.t()}
  defp create_watch(node_id, watcher_type, watcher_ref) do
    normalized_node_id = normalize_id(node_id)

    case Repo.get(Node, normalized_node_id) do
      %Node{} = node ->
        watch =
          case Repo.get_by(NodeWatcher,
                 node_id: normalized_node_id,
                 watcher_type: watcher_type,
                 watcher_ref: watcher_ref
               ) do
            %NodeWatcher{} = existing ->
              existing

            nil ->
              %NodeWatcher{}
              |> NodeWatcher.changeset(%{
                node_id: normalized_node_id,
                watcher_type: watcher_type,
                watcher_ref: watcher_ref
              })
              |> Repo.insert!()
          end

        :ok = Nodes.refresh_watcher_metrics!(node.id)
        {:ok, watch}

      nil ->
        {:error, :node_not_found}
    end
  end

  @spec delete_watch(integer() | String.t(), atom(), integer()) :: :ok | {:error, :node_not_found}
  defp delete_watch(node_id, watcher_type, watcher_ref) do
    normalized_node_id = normalize_id(node_id)

    case Repo.get(Node, normalized_node_id) do
      %Node{} = node ->
        NodeWatcher
        |> where([w], w.node_id == ^normalized_node_id)
        |> where([w], w.watcher_type == ^watcher_type)
        |> where([w], w.watcher_ref == ^watcher_ref)
        |> Repo.delete_all()

        :ok = Nodes.refresh_watcher_metrics!(node.id)
        :ok

      nil ->
        {:error, :node_not_found}
    end
  end

  @spec normalize_session_id(integer() | String.t()) :: String.t()
  defp normalize_session_id(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_session_id(value) when is_binary(value), do: String.trim(value)

  @spec maybe_before_cursor(Ecto.Query.t(), integer() | nil) :: Ecto.Query.t()
  defp maybe_before_cursor(query, nil), do: query
  defp maybe_before_cursor(query, cursor), do: where(query, [w], w.id < ^cursor)

  @spec online_sessions_key(integer()) :: String.t()
  defp online_sessions_key(node_id), do: "#{@cache_prefix}:node:#{node_id}:online_sessions"

  @spec online_session_topic(String.t()) :: String.t()
  defp online_session_topic(session_ref), do: "#{@cache_prefix}:session:#{session_ref}"

  @spec online_session_ref(String.t()) :: String.t()
  defp online_session_ref(session_id) do
    session_id
    |> String.trim()
    |> RegentCache.digest()
  end

  @spec watcher_node_topic(atom(), integer(), integer()) :: String.t()
  defp watcher_node_topic(watcher_type, watcher_ref, node_id) do
    "watcher:#{watcher_type}:#{watcher_ref}:node:#{node_id}"
  end

  @spec build_fanout_payload(integer(), atom(), integer()) :: map()
  defp build_fanout_payload(node_id, watcher_type, watcher_ref) do
    %{
      event: "node_activity",
      node_id: node_id,
      watcher_type: Atom.to_string(watcher_type),
      watcher_ref: watcher_ref
    }
  end
end
