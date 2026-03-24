defmodule TechTree.HumanUX do
  @moduledoc false

  alias TechTree.{Comments, Nodes}
  alias TechTree.Nodes.Node

  @seed_hot_limit 24
  @seed_graph_limit 60
  @node_children_limit %{"limit" => "40"}
  @node_comments_limit %{"limit" => "60"}

  @type seed_card :: %{
          seed: String.t(),
          branch_count: non_neg_integer(),
          top_title: String.t(),
          top_summary: String.t() | nil
        }

  @type related_node :: %{
          dst_id: integer(),
          dst_title: String.t() | nil,
          tag: String.t(),
          ordinal: integer()
        }

  @type node_page :: %{
          node: Node.t(),
          parent: Node.t() | nil,
          lineage: [Node.t()],
          children: [Node.t()],
          related: [related_node()],
          comments: [TechTree.Comments.Comment.t()]
        }

  @type seed_lane :: %{
          seed: String.t(),
          branch_count: non_neg_integer(),
          top_title: String.t(),
          top_summary: String.t() | nil,
          branches: [Node.t()],
          graph_nodes: [map()]
        }

  @type seed_page :: %{
          known_seed?: boolean(),
          branches: [Node.t()],
          graph_nodes: [map()]
        }

  @spec seed_roots() :: [String.t()]
  def seed_roots, do: Nodes.seed_roots()

  @spec seed?(String.t()) :: boolean()
  def seed?(seed) when is_binary(seed), do: seed in seed_roots()
  def seed?(_seed), do: false

  @spec seed_view(String.t() | nil) :: :branch | :graph
  def seed_view("graph"), do: :graph
  def seed_view(_value), do: :branch

  @spec seed_cards() :: [seed_card()]
  def seed_cards do
    seed_roots()
    |> Enum.map(&seed_lane/1)
    |> Enum.map(fn lane ->
      %{
        seed: lane.seed,
        branch_count: lane.branch_count,
        top_title: lane.top_title,
        top_summary: lane.top_summary
      }
    end)
  end

  @spec branches_for_seed(String.t()) :: [Node.t()]
  def branches_for_seed(seed) when is_binary(seed) do
    hot_nodes_for_seed(seed, @seed_hot_limit)
  end

  @spec graph_for_seed(String.t()) :: [map()]
  def graph_for_seed(seed) when is_binary(seed) do
    seed
    |> hot_nodes_for_seed(@seed_graph_limit)
    |> graph_nodes_from()
  end

  @spec seed_lanes() :: [seed_lane()]
  def seed_lanes do
    Enum.map(seed_roots(), &seed_lane/1)
  end

  @spec seed_lane(String.t()) :: seed_lane()
  def seed_lane(seed) when is_binary(seed) do
    nodes = hot_nodes_for_seed(seed, @seed_graph_limit)
    branches = Enum.take(nodes, @seed_hot_limit)
    top = List.first(branches)

    %{
      seed: seed,
      branch_count: length(branches),
      top_title: if(top, do: top.title, else: "No live branches yet"),
      top_summary: if(top, do: top.summary, else: nil),
      branches: branches,
      graph_nodes: graph_nodes_from(nodes)
    }
  end

  @spec seed_page(String.t()) :: seed_page()
  def seed_page(seed) when is_binary(seed) do
    if seed?(seed) do
      lane = seed_lane(seed)

      %{
        known_seed?: true,
        branches: lane.branches,
        graph_nodes: lane.graph_nodes
      }
    else
      %{known_seed?: false, branches: [], graph_nodes: []}
    end
  end

  @spec node_page(integer() | String.t()) :: {:ok, node_page()} | :error
  def node_page(node_id) do
    with {:ok, normalized_id} <- parse_node_id(node_id),
         {:ok, node} <- fetch_public_node(normalized_id) do
      lineage = build_lineage(node)

      {:ok,
       %{
         node: node,
         parent: List.last(lineage),
         lineage: lineage,
         children: Nodes.list_public_children(node.id, @node_children_limit),
         related: related_nodes(node.id),
         comments: Comments.list_public_for_node(node.id, @node_comments_limit)
       }}
    end
  end

  @spec parse_node_id(integer() | String.t()) :: {:ok, integer()} | :error
  defp parse_node_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_node_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_node_id(_value), do: :error

  @spec fetch_public_node(integer()) :: {:ok, Node.t()} | :error
  defp fetch_public_node(id) do
    {:ok, Nodes.get_public_node!(id)}
  rescue
    Ecto.NoResultsError -> :error
  end

  @spec build_lineage(Node.t()) :: [Node.t()]
  defp build_lineage(node) do
    case lineage_ids_from_path(node) do
      [] ->
        build_lineage_from_parent(node.parent_id, [])

      ids ->
        resolved_nodes = nodes_by_id(ids)

        if map_size(resolved_nodes) == length(ids) do
          ordered_nodes_for(resolved_nodes, ids)
        else
          build_lineage_from_parent(node.parent_id, [])
        end
    end
  end

  @spec build_lineage_from_parent(integer() | nil, [Node.t()]) :: [Node.t()]
  defp build_lineage_from_parent(nil, acc), do: Enum.reverse(acc)

  defp build_lineage_from_parent(parent_id, acc) when is_integer(parent_id) do
    case fetch_public_node(parent_id) do
      {:ok, parent} -> build_lineage_from_parent(parent.parent_id, [parent | acc])
      :error -> Enum.reverse(acc)
    end
  end

  defp build_lineage_from_parent(_parent_id, acc), do: Enum.reverse(acc)

  @spec related_nodes(integer()) :: [related_node()]
  defp related_nodes(node_id) do
    edges = Nodes.list_tagged_edges(node_id)

    titles_by_id =
      edges
      |> Enum.map(& &1.dst_node_id)
      |> Enum.uniq()
      |> nodes_by_id()
      |> Map.new(fn {id, node} -> {id, node.title} end)

    Enum.map(edges, fn edge ->
      %{
        dst_id: edge.dst_node_id,
        dst_title: Map.get(titles_by_id, edge.dst_node_id),
        tag: edge.tag,
        ordinal: edge.ordinal
      }
    end)
  end

  @spec hot_nodes_for_seed(String.t(), pos_integer()) :: [Node.t()]
  defp hot_nodes_for_seed(seed, limit) when is_binary(seed) and is_integer(limit) and limit > 0 do
    if seed?(seed) do
      Nodes.list_hot_nodes(seed, %{"limit" => Integer.to_string(limit)})
    else
      []
    end
  end

  @spec graph_nodes_from([Node.t()]) :: [map()]
  defp graph_nodes_from(nodes) do
    Enum.map(nodes, fn node ->
      %{
        id: node.id,
        parent_id: node.parent_id,
        depth: node.depth,
        title: node.title,
        kind: node.kind,
        child_count: node.child_count,
        watcher_count: node.watcher_count
      }
    end)
  end

  @spec lineage_ids_from_path(Node.t()) :: [integer()]
  defp lineage_ids_from_path(%Node{path: path, id: node_id}) when is_binary(path) do
    ids =
      path
      |> String.split(".", trim: true)
      |> Enum.map(&parse_path_node_id/1)
      |> Enum.reject(&is_nil/1)

    drop_current_node_id(ids, node_id)
  end

  defp lineage_ids_from_path(_node), do: []

  @spec parse_path_node_id(String.t()) :: integer() | nil
  defp parse_path_node_id("n" <> raw_id) do
    case Integer.parse(raw_id) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp parse_path_node_id(_label), do: nil

  @spec drop_current_node_id([integer()], integer() | nil) :: [integer()]
  defp drop_current_node_id([], _node_id), do: []

  defp drop_current_node_id(ids, node_id) do
    case Enum.reverse(ids) do
      [^node_id | rest] -> Enum.reverse(rest)
      _ -> ids
    end
  end

  @spec nodes_by_id([integer()]) :: %{optional(integer()) => Node.t()}
  defp nodes_by_id(ids) do
    ids
    |> Nodes.list_public_nodes_by_ids()
    |> Map.new(fn node -> {node.id, node} end)
  end

  @spec ordered_nodes_for(%{optional(integer()) => Node.t()}, [integer()]) :: [Node.t()]
  defp ordered_nodes_for(nodes_by_id, ids) do
    Enum.flat_map(ids, fn id ->
      case Map.fetch(nodes_by_id, id) do
        {:ok, node} -> [node]
        :error -> []
      end
    end)
  end
end
