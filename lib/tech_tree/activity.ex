defmodule TechTree.Activity do
  @moduledoc false

  import Ecto.Query
  import TechTree.QueryHelpers

  alias TechTree.Repo
  alias TechTree.Activity.ActivityEvent
  alias TechTree.Nodes.Node

  @spec list_public_events(map()) :: [ActivityEvent.t()]
  def list_public_events(params) do
    limit = parse_limit(params, 50)

    ActivityEvent
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec list_public_events_for_node(integer() | String.t(), map()) :: [ActivityEvent.t()]
  def list_public_events_for_node(node_id, params \\ %{}) do
    normalized_node_id = normalize_id(node_id)
    limit = parse_limit(params, 50)

    ActivityEvent
    |> where([e], e.subject_node_id == ^normalized_node_id)
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec list_agent_feed_events(integer(), map()) :: [ActivityEvent.t()]
  def list_agent_feed_events(agent_id, params \\ %{})
      when is_integer(agent_id) and agent_id > 0 do
    limit = parse_limit(params, 50)
    cursor = parse_cursor(params)
    seed_filter = parse_seed_filter(params)
    kind_filters = parse_kind_filters(params)

    owned_node_ids_query =
      Node
      |> where([n], n.creator_agent_id == ^agent_id)
      |> where([n], n.status == :anchored)
      |> where([n], n.creator_agent_id in subquery(active_agent_ids_query()))
      |> select([n], n.id)

    watched_node_ids_query =
      TechTree.Watches.NodeWatcher
      |> where([w], w.watcher_type == :agent and w.watcher_ref == ^agent_id)
      |> select([w], w.node_id)

    ActivityEvent
    |> where(
      [e],
      (e.actor_type == :agent and e.actor_ref == ^agent_id) or
        e.subject_node_id in subquery(owned_node_ids_query) or
        e.subject_node_id in subquery(watched_node_ids_query)
    )
    |> maybe_filter_feed_scope(seed_filter, kind_filters)
    |> maybe_apply_cursor(cursor)
    |> maybe_apply_feed_order(cursor)
    |> limit(^limit)
    |> Repo.all()
    |> maybe_reverse_feed(cursor)
  end

  @spec log!(String.t(), String.t() | atom(), integer() | nil, integer() | nil, map()) ::
          ActivityEvent.t()
  def log!(event_type, actor_type, actor_ref, subject_node_id, payload \\ %{}) do
    %ActivityEvent{}
    |> ActivityEvent.changeset(%{
      event_type: event_type,
      actor_type: actor_type,
      actor_ref: actor_ref,
      subject_node_id: subject_node_id,
      payload: payload
    })
    |> Repo.insert!()
  end

  @spec classify_stream(ActivityEvent.t() | String.t() | nil) :: ActivityEvent.stream_type()
  def classify_stream(event_or_type), do: ActivityEvent.stream_type(event_or_type)

  @spec maybe_filter_feed_scope(Ecto.Query.t(), String.t() | nil, [Node.kind()]) :: Ecto.Query.t()
  defp maybe_filter_feed_scope(query, nil, []), do: query

  defp maybe_filter_feed_scope(query, seed_filter, kind_filters) do
    scoped_nodes_query =
      Node
      |> where([n], n.status == :anchored)
      |> where([n], n.creator_agent_id in subquery(active_agent_ids_query()))
      |> maybe_filter_nodes_seed(seed_filter)
      |> maybe_filter_nodes_kind(kind_filters)
      |> select([n], n.id)

    query
    |> where([e], not is_nil(e.subject_node_id))
    |> where([e], e.subject_node_id in subquery(scoped_nodes_query))
  end

  @spec maybe_filter_nodes_seed(Ecto.Query.t(), String.t() | nil) :: Ecto.Query.t()
  defp maybe_filter_nodes_seed(query, nil), do: query
  defp maybe_filter_nodes_seed(query, seed), do: where(query, [n], n.seed == ^seed)

  @spec maybe_filter_nodes_kind(Ecto.Query.t(), [Node.kind()]) :: Ecto.Query.t()
  defp maybe_filter_nodes_kind(query, []), do: query
  defp maybe_filter_nodes_kind(query, kinds), do: where(query, [n], n.kind in ^kinds)

  @spec maybe_apply_cursor(Ecto.Query.t(), integer() | nil) :: Ecto.Query.t()
  defp maybe_apply_cursor(query, nil), do: query
  defp maybe_apply_cursor(query, cursor), do: where(query, [e], e.id > ^cursor)

  @spec maybe_apply_feed_order(Ecto.Query.t(), integer() | nil) :: Ecto.Query.t()
  defp maybe_apply_feed_order(query, nil), do: order_by(query, [e], desc: e.id)
  defp maybe_apply_feed_order(query, _cursor), do: order_by(query, [e], asc: e.id)

  @spec maybe_reverse_feed([ActivityEvent.t()], integer() | nil) :: [ActivityEvent.t()]
  defp maybe_reverse_feed(events, nil), do: Enum.reverse(events)
  defp maybe_reverse_feed(events, _cursor), do: events

  @spec parse_seed_filter(map()) :: String.t() | nil
  defp parse_seed_filter(params) do
    case Map.get(params, "seed") do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  @spec parse_kind_filters(map()) :: [Node.kind()]
  defp parse_kind_filters(params) do
    allowed_kinds_by_name =
      Node.node_kinds()
      |> Enum.reduce(%{}, fn kind, acc -> Map.put(acc, Atom.to_string(kind), kind) end)

    params
    |> Map.get("kind")
    |> List.wrap()
    |> Enum.flat_map(fn
      value when is_binary(value) ->
        value
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)

      _ ->
        []
    end)
    |> Enum.map(&Map.get(allowed_kinds_by_name, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

end
