defmodule TechTree.HumanUX do
  @moduledoc false

  alias TechTree.{Comments, Nodes}
  alias TechTree.Nodes.Node

  @seed_hot_limit 24
  @seed_graph_limit 60
  @node_children_limit %{"limit" => "40"}
  @node_comments_limit %{"limit" => "60"}
  @cross_chain_summary_threshold 24

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

  @type cross_chain_claim :: %{
          relation_label: String.t(),
          note: String.t() | nil,
          claimant_label: String.t() | nil,
          target_label: String.t() | nil,
          declared_by_author: boolean(),
          mutual?: boolean(),
          disputed?: boolean()
        }

  @type cross_chain_lineage :: %{
          author_claim: cross_chain_claim() | nil,
          claims: [cross_chain_claim()],
          summary: %{
            total: non_neg_integer(),
            author_claims: non_neg_integer(),
            mutual_claims: non_neg_integer(),
            disputed_claims: non_neg_integer(),
            relation_buckets: [map()]
          },
          summary_mode: boolean()
        }

  @type node_page :: %{
          node: Node.t(),
          parent: Node.t() | nil,
          lineage: [Node.t()],
          children: [Node.t()],
          related: [related_node()],
          comments: [TechTree.Comments.Comment.t()],
          cross_chain_lineage: cross_chain_lineage() | nil
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
    branches = seed_branch_roots(seed)
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
         comments: Comments.list_public_for_node(node.id, @node_comments_limit),
         cross_chain_lineage: cross_chain_lineage(node)
       }}
    end
  end

  @spec cross_chain_lineage(Node.t() | map()) :: cross_chain_lineage() | nil
  def cross_chain_lineage(node) when is_map(node) do
    case Map.get(node, :cross_chain_lineage) do
      nil ->
        nil

      data ->
        claims = normalize_cross_chain_claims(data, Map.get(node, :creator_agent_id))

        case claims do
          [] ->
            nil

          _ ->
            {author_claim, non_author_claims} = split_author_claim(claims)
            all_claims = maybe_prepend_author_claim(non_author_claims, author_claim)

            %{
              author_claim: author_claim,
              claims: non_author_claims,
              summary: cross_chain_summary(all_claims),
              summary_mode: length(all_claims) > @cross_chain_summary_threshold
            }
        end
    end
  end

  def cross_chain_lineage(_node), do: nil

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

  @spec seed_branch_roots(String.t()) :: [Node.t()]
  defp seed_branch_roots(seed) do
    case Enum.find(Nodes.list_public_seed_roots(), &(&1.seed == seed)) do
      %Node{} = root ->
        Nodes.list_public_children(root.id, %{"limit" => Integer.to_string(@seed_hot_limit)})

      _ ->
        []
    end
  end

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

  @spec normalize_cross_chain_claims(term(), integer() | nil) :: [cross_chain_claim()]
  defp normalize_cross_chain_claims(data, creator_agent_id) when is_list(data) do
    data
    |> Enum.flat_map(&normalize_cross_chain_claims(&1, creator_agent_id))
    |> Enum.reject(&is_nil/1)
    |> sort_cross_chain_claims()
  end

  defp normalize_cross_chain_claims(%{} = data, creator_agent_id) do
    cond do
      Map.has_key?(data, :claims) or Map.has_key?(data, "claims") or
        Map.has_key?(data, :author_claim) or
          Map.has_key?(data, "author_claim") ->
        claims =
          case Map.get(data, :claims) || Map.get(data, "claims") do
            nil -> []
            list -> List.wrap(list)
          end

        author_claims =
          case Map.get(data, :author_claim) || Map.get(data, "author_claim") do
            nil -> []
            author -> List.wrap(author)
          end

        (claims ++ author_claims)
        |> Enum.flat_map(&normalize_cross_chain_claims(&1, creator_agent_id))
        |> Enum.reject(&is_nil/1)
        |> sort_cross_chain_claims()

      true ->
        case normalize_cross_chain_claim(data, creator_agent_id) do
          nil -> []
          claim -> [claim]
        end
    end
  end

  defp normalize_cross_chain_claims(_data, _creator_agent_id), do: []

  @spec normalize_cross_chain_claim(term(), integer() | nil) :: cross_chain_claim() | nil
  defp normalize_cross_chain_claim(%{} = claim, creator_agent_id) do
    relation = claim_value(claim, :relation) || claim_value(claim, "relation")

    if is_binary(relation) and String.trim(relation) != "" do
      claimant_agent_id =
        claim_value(claim, :claimant_agent_id) || claim_value(claim, "claimant_agent_id")

      note = claim_value(claim, :note) || claim_value(claim, "note")

      %{
        relation_label: relation_label(relation),
        note: trim_optional_text(note),
        claimant_label: claim_display_label(claim),
        target_label: target_label(claim),
        declared_by_author: author_claim?(claim, claimant_agent_id, creator_agent_id),
        mutual?:
          truthy?(
            claim_value(claim, :mutual) ||
              claim_value(claim, "mutual") ||
              claim_value(claim, :mutually_linked) ||
              claim_value(claim, "mutually_linked")
          ),
        disputed?:
          truthy?(
            claim_value(claim, :disputed) ||
              claim_value(claim, "disputed") ||
              claim_value(claim, :status) == "disputed" ||
              claim_value(claim, "status") == "disputed"
          )
      }
    end
  end

  defp normalize_cross_chain_claim(_claim, _creator_agent_id), do: nil

  @spec split_author_claim([cross_chain_claim()]) ::
          {cross_chain_claim() | nil, [cross_chain_claim()]}
  defp split_author_claim(claims) do
    case Enum.split_with(claims, & &1.declared_by_author) do
      {[], rest} -> {nil, rest}
      {[author_claim | rest], others} -> {author_claim, rest ++ others}
    end
  end

  @spec maybe_prepend_author_claim([cross_chain_claim()], cross_chain_claim() | nil) :: [
          cross_chain_claim()
        ]
  defp maybe_prepend_author_claim(claims, nil), do: claims
  defp maybe_prepend_author_claim(claims, author_claim), do: [author_claim | claims]

  @spec sort_cross_chain_claims([cross_chain_claim()]) :: [cross_chain_claim()]
  defp sort_cross_chain_claims(claims) do
    Enum.sort_by(
      claims,
      fn claim ->
        {
          claim.declared_by_author,
          claim.disputed?,
          claim.mutual?,
          String.downcase(claim.relation_label || ""),
          String.downcase(claim.target_label || "")
        }
      end,
      :desc
    )
  end

  @spec cross_chain_summary([cross_chain_claim()]) :: %{
          total: non_neg_integer(),
          author_claims: non_neg_integer(),
          mutual_claims: non_neg_integer(),
          disputed_claims: non_neg_integer(),
          relation_buckets: [map()]
        }
  defp cross_chain_summary(claims) do
    total = length(claims)
    author_claims = Enum.count(claims, & &1.declared_by_author)
    mutual_claims = Enum.count(claims, & &1.mutual?)
    disputed_claims = Enum.count(claims, & &1.disputed?)

    relation_buckets =
      claims
      |> Enum.frequencies_by(& &1.relation_label)
      |> Enum.sort_by(fn {_relation, count} -> count end, :desc)
      |> Enum.take(6)
      |> Enum.map(fn {relation, count} ->
        %{
          label: relation,
          count: count,
          percent: if(total > 0, do: round(count * 100 / total), else: 0)
        }
      end)

    %{
      total: total,
      author_claims: author_claims,
      mutual_claims: mutual_claims,
      disputed_claims: disputed_claims,
      relation_buckets: relation_buckets
    }
  end

  defp relation_label(relation) when is_binary(relation) do
    relation
    |> String.replace("_", " ")
    |> String.trim()
  end

  defp relation_label(relation), do: to_string(relation)

  defp claimant_label(nil), do: nil
  defp claimant_label(value) when is_integer(value), do: "Agent ##{value}"

  defp claimant_label(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp target_label(claim) do
    explicit =
      claim_value(claim, :target_label) ||
        claim_value(claim, "target_label") ||
        claim_value(claim, :target_node_title) ||
        claim_value(claim, "target_node_title")

    if is_binary(explicit) and String.trim(explicit) != "" do
      String.trim(explicit)
    else
      chain_label =
        claim_value(claim, :target_chain_label) || claim_value(claim, "target_chain_label")

      target_ref = claim_value(claim, :target_node_ref) || claim_value(claim, "target_node_ref")

      chain_id = claim_value(claim, :target_chain_id) || claim_value(claim, "target_chain_id")
      node_id = claim_value(claim, :target_node_id) || claim_value(claim, "target_node_id")

      case {chain_label, chain_id, node_id, target_ref} do
        {label, _chain, _node, _ref} when is_binary(label) and label != "" ->
          case {node_id, target_ref} do
            {node, _ref} when not is_nil(node) -> "#{label} · Node #{node}"
            {_node, ref} when is_binary(ref) and ref != "" -> "#{label} · #{ref}"
            _ -> label
          end

        {nil, nil, nil, nil} ->
          nil

        {nil, chain, nil, nil} ->
          "Chain #{chain}"

        {nil, nil, node, nil} ->
          "Node #{node}"

        {nil, chain, node, nil} ->
          "Chain #{chain} · Node #{node}"

        {nil, chain, nil, ref} ->
          "Chain #{chain} · #{ref}"

        {nil, nil, node, ref} ->
          "Node #{node} · #{ref}"

        {nil, chain, node, ref} ->
          "Chain #{chain} · Node #{node} · #{ref}"
      end
    end
  end

  defp author_claim?(claim, claimant_agent_id, creator_agent_id) do
    truthy?(
      claim_value(claim, :declared_by_author) ||
        claim_value(claim, "declared_by_author") ||
        claim_value(claim, :author_claim) ||
        claim_value(claim, "author_claim")
    ) ||
      (is_integer(creator_agent_id) and claimant_agent_id == creator_agent_id) ||
      truthy?(claim_value(claim, :claimed_by_author) || claim_value(claim, "claimed_by_author"))
  end

  defp trim_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim_optional_text(_value), do: nil

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(1), do: true
  defp truthy?("1"), do: true
  defp truthy?(_value), do: false

  defp claim_value(map, key) when is_map(map), do: Map.get(map, key)

  defp claim_display_label(claim) when is_map(claim) do
    explicit = claim_value(claim, :claimant_label) || claim_value(claim, "claimant_label")

    if is_binary(explicit) and String.trim(explicit) != "" do
      String.trim(explicit)
    else
      claimant_agent_id =
        claim_value(claim, :claimant_agent_id) || claim_value(claim, "claimant_agent_id")

      claimant_label(claimant_agent_id)
    end
  end

  defp claim_display_label(_claim), do: nil

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
        watcher_count: node.watcher_count,
        comment_count: node.comment_count,
        creator_agent_id: node.creator_agent_id,
        activity_score: node.activity_score
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
