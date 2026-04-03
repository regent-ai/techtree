defmodule TechTreeWeb.HomeLive.Dataset do
  @moduledoc false

  import Ecto.Query, only: [where: 3, select: 3]

  alias TechTree.Agents.AgentIdentity
  alias TechTree.{HumanUX, Nodes, Repo}
  alias TechTreeWeb.HomePresenter

  @fixture_creator_addresses [
    "0x1111111111111111111111111111111111111111",
    "0x2222222222222222222222222222222222222222",
    "0x3333333333333333333333333333333333333333",
    "0x4444444444444444444444444444444444444444",
    "0x5555555555555555555555555555555555555555"
  ]
  @seed_catalog [
    %{seed: "ML", label: "Machine Learning", note: "foundation models and applied systems"},
    %{seed: "Skills", label: "Agent Skills.md", note: "operator playbooks and reusable patterns"},
    %{seed: "Polymarket", label: "Polymarket Positions", note: "market books and event theses"},
    %{
      seed: "Firmware",
      label: "Home/Robotics Firmware",
      note: "devices, motion control, and embedded work"
    },
    %{seed: "DeFi", label: "DeFi Positions", note: "onchain capital, protocols, and vaults"},
    %{
      seed: "Bioscience",
      label: "Protein Binders",
      note: "molecular design and wet-lab programs"
    },
    %{seed: "Evals", label: "Agent Evals", note: "benchmarks, scorecards, and harnesses"}
  ]

  def build(requested_mode, dev_dataset_toggle?) do
    data_mode = normalize_mode(requested_mode, dev_dataset_toggle?)

    graph_nodes =
      data_mode
      |> dataset_graph_nodes()
      |> enrich_graph_agents()

    seed_catalog = seed_catalog(graph_nodes)
    graph_nodes = layout_graph_nodes(graph_nodes, seed_catalog)
    graph_edges = graph_edges(graph_nodes)
    graph_meta = HomePresenter.graph_meta(graph_nodes, graph_edges)
    selected_node = default_selected_node(graph_nodes)
    agent_focus_options = HomePresenter.agent_focus_options(graph_nodes)

    %{
      agent_focus_options: agent_focus_options,
      data_mode: data_mode,
      graph_nodes: graph_nodes,
      graph_edges: graph_edges,
      graph_meta: graph_meta,
      seed_catalog: seed_catalog,
      agent_labels_by_id: HomePresenter.agent_labels_by_id(graph_nodes),
      graph_agent_query: "",
      graph_agent_matches: HomePresenter.matching_agent_focus_options(agent_focus_options, ""),
      node_query: "",
      node_matches: [],
      selected_node_id: selected_node && selected_node.id,
      selected_node: selected_node,
      node_focus_target_id: nil,
      selected_agent_id: nil,
      subtree_root_id: nil,
      subtree_mode: nil,
      show_null_results?: false,
      filter_to_null_results?: false,
      graph_node_index: Map.new(graph_nodes, &{&1.id, &1}),
      graph_children_by_parent: graph_children_by_parent(graph_nodes)
    }
  end

  def seed_catalog_definitions, do: @seed_catalog

  defp normalize_mode("fixture", true), do: "fixture"
  defp normalize_mode(_requested_mode, _dev_dataset_toggle?), do: "live"

  defp seed_catalog(graph_nodes) do
    live_seeds = graph_nodes |> Enum.map(& &1.seed) |> Enum.reject(&is_nil/1) |> MapSet.new()

    @seed_catalog
    |> Enum.filter(fn %{seed: seed} -> MapSet.member?(live_seeds, seed) end)
    |> Kernel.++(
      graph_nodes
      |> Enum.map(& &1.seed)
      |> Enum.uniq()
      |> Enum.reject(fn seed -> Enum.any?(@seed_catalog, &(&1.seed == seed)) end)
      |> Enum.map(fn seed ->
        %{seed: seed, label: seed, note: "live seed root"}
      end)
    )
  end

  defp dataset_graph_nodes("fixture"), do: fixture_graph_nodes()
  defp dataset_graph_nodes(_mode), do: public_graph_nodes()

  defp fixture_graph_nodes do
    seeds = Enum.take(@seed_catalog, 6)
    child_kinds = ["hypothesis", "data", "review", "synthesis", "skill"]
    grandchild_kinds = ["result", "meta", "result", "review", "null_result"]

    {roots, next_id} =
      Enum.map_reduce(seeds, 700_000, fn seed_meta, id ->
        root =
          fixture_node(%{
            id: id,
            parent_id: nil,
            depth: 0,
            path: "n#{id}",
            title: "#{seed_meta.label} seed root",
            seed: seed_meta.seed,
            kind: "hypothesis",
            summary: "Fixture root for #{seed_meta.label}.",
            creator_address: fixture_creator_address(id)
          })

        {root, id + 1}
      end)

    {children, next_id} =
      Enum.map_reduce(Enum.with_index(roots), next_id, fn {root, root_index}, id_start ->
        nodes =
          Enum.map(1..5, fn child_index ->
            child_id = id_start + child_index - 1
            kind = Enum.at(child_kinds, rem(child_index + root_index, length(child_kinds)))

            fixture_node(%{
              id: child_id,
              parent_id: root.id,
              depth: 1,
              path: "#{root.path}.n#{child_id}",
              title:
                "#{HomePresenter.display_seed_label(root.seed, @seed_catalog)} branch #{child_index}",
              seed: root.seed,
              kind: kind,
              summary:
                "Fixture child #{child_index} under #{HomePresenter.display_seed_label(root.seed, @seed_catalog)} from #{HomePresenter.short_creator_address(fixture_creator_address(child_id))}.",
              creator_address: fixture_creator_address(child_id),
              watcher_count: 8 + root_index + child_index,
              comment_count: 2 + rem(child_index, 3)
            })
          end)

        {nodes, id_start + 5}
      end)

    flat_children = List.flatten(children)

    grandchildren =
      flat_children
      |> Enum.take(14)
      |> Enum.with_index(next_id)
      |> Enum.map(fn {parent, grandchild_id} ->
        kind = Enum.at(grandchild_kinds, rem(grandchild_id, length(grandchild_kinds)))

        fixture_node(%{
          id: grandchild_id,
          parent_id: parent.id,
          depth: 2,
          path: "#{parent.path}.n#{grandchild_id}",
          title: "#{parent.title} outcome",
          seed: parent.seed,
          kind: kind,
          summary:
            "Fixture grandchild attached to #{parent.title}, demonstrating nested descendants inside the test lattice.",
          creator_address: fixture_creator_address(grandchild_id),
          watcher_count: 6 + rem(grandchild_id, 7),
          comment_count: 1 + rem(grandchild_id, 4)
        })
      end)

    all_nodes = roots ++ flat_children ++ grandchildren
    child_counts = all_nodes |> Enum.frequencies_by(& &1.parent_id) |> Map.delete(nil)

    Enum.map(all_nodes, fn node ->
      Map.put(node, :child_count, Map.get(child_counts, node.id, 0))
    end)
    |> Enum.sort_by(fn node ->
      {node.depth, node.seed, node.path, node.id}
    end)
  end

  defp fixture_node(attrs) do
    id = attrs.id

    %{
      id: id,
      parent_id: Map.get(attrs, :parent_id),
      depth: Map.get(attrs, :depth, 0),
      title: Map.get(attrs, :title, "Fixture node #{id}"),
      path: Map.get(attrs, :path, "n#{id}"),
      kind: Map.get(attrs, :kind, "hypothesis"),
      seed: Map.fetch!(attrs, :seed),
      child_count: Map.get(attrs, :child_count, 0),
      watcher_count: Map.get(attrs, :watcher_count, 10 + rem(id, 9)),
      comment_count: Map.get(attrs, :comment_count, 1 + rem(id, 5)),
      summary: Map.get(attrs, :summary),
      status: Map.get(attrs, :status, "pinned"),
      creator_address: Map.get(attrs, :creator_address),
      creator_agent_id: Map.get(attrs, :creator_agent_id, 1 + rem(id, 5)),
      inserted_at: Map.get(attrs, :inserted_at)
    }
  end

  defp fixture_creator_address(id) do
    Enum.at(@fixture_creator_addresses, rem(id, length(@fixture_creator_addresses)))
  end

  defp public_graph_nodes do
    source_nodes =
      Nodes.list_public_seed_roots()
      |> Enum.map(&base_graph_node(&1, &1.seed))
      |> Kernel.++(
        HumanUX.seed_lanes()
        |> Enum.flat_map(fn lane ->
          Enum.map(lane.graph_nodes, fn node ->
            base_graph_node(node, lane.seed)
          end)
        end)
      )
      |> Enum.uniq_by(& &1.id)

    if live_graph_ready?(source_nodes) do
      enrich_graph_nodes(source_nodes)
    else
      fallback_graph_nodes()
    end
  end

  defp live_graph_ready?(nodes) do
    length(nodes) > length(@seed_catalog) or
      Enum.any?(nodes, fn node ->
        is_integer(node.parent_id) or (node.depth || 0) > 0
      end)
  end

  defp enrich_graph_nodes(nodes) do
    details =
      nodes
      |> Enum.map(& &1.id)
      |> Nodes.list_public_nodes_by_ids()
      |> Map.new(fn node -> {node.id, node} end)

    Enum.map(nodes, fn node ->
      detail = Map.get(details, node.id)

      Map.merge(node, %{
        path: if(detail, do: detail.path, else: node[:path]),
        comment_count: if(detail, do: detail.comment_count || 0, else: 0),
        status: if(detail, do: Atom.to_string(detail.status || :pinned), else: "pinned"),
        summary: if(detail, do: HomePresenter.trim_summary(detail.summary), else: nil),
        creator_agent_id: if(detail, do: detail.creator_agent_id, else: node[:creator_agent_id]),
        inserted_at:
          if(detail, do: graph_timestamp(detail.inserted_at), else: node[:inserted_at]),
        label: if(detail, do: detail.title || node.title, else: node.title)
      })
    end)
    |> Enum.sort_by(fn node ->
      {node.seed, node.depth, -(node.watcher_count || 0), -(node.child_count || 0), node.id}
    end)
  end

  defp fallback_graph_nodes do
    now = DateTime.utc_now()

    HumanUX.seed_roots()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {seed, seed_index} ->
      root_id = seed_index * 1_000

      [
        %{
          id: root_id,
          parent_id: nil,
          depth: 0,
          title: "#{seed} root",
          path: "n#{root_id}",
          kind: "seed",
          seed: seed,
          child_count: 2,
          watcher_count: 12 - seed_index,
          comment_count: 4,
          status: "anchored",
          summary: "Fallback scaffold for the homepage graph.",
          creator_address: nil,
          creator_agent_id: 1 + rem(root_id, 5),
          inserted_at: now
        },
        %{
          id: root_id + 1,
          parent_id: root_id,
          depth: 1,
          title: "#{seed} active branch",
          path: "n#{root_id}.n#{root_id + 1}",
          kind: "hypothesis",
          seed: seed,
          child_count: 3,
          watcher_count: 7 + seed_index,
          comment_count: 2,
          status: "pinned",
          summary: "A live branch slot for the homepage route.",
          creator_address: nil,
          creator_agent_id: 1 + rem(root_id + 1, 5),
          inserted_at: now
        },
        %{
          id: root_id + 2,
          parent_id: root_id + 1,
          depth: 2,
          title: "#{seed} validated result",
          path: "n#{root_id}.n#{root_id + 1}.n#{root_id + 2}",
          kind: "result",
          seed: seed,
          child_count: 1,
          watcher_count: 4 + seed_index,
          comment_count: 1,
          status: "pinned",
          summary: "A second-layer node so the deck.gl scene always has a visible tree.",
          creator_address: nil,
          creator_agent_id: 1 + rem(root_id + 2, 5),
          inserted_at: now
        }
      ]
    end)
  end

  defp default_selected_node([]), do: nil

  defp default_selected_node(graph_nodes) do
    Enum.max_by(
      graph_nodes,
      fn node ->
        {node.watcher_count || 0, node.child_count || 0, -(node.depth || 0), -node.id}
      end
    )
  end

  defp base_graph_node(node, seed) do
    %{
      id: Map.get(node, :id),
      parent_id: Map.get(node, :parent_id),
      depth: Map.get(node, :depth, 0) || 0,
      title: Map.get(node, :title) || "Untitled node",
      label: Map.get(node, :title) || "Untitled node",
      path: Map.get(node, :path),
      kind: to_string(Map.get(node, :kind) || "node"),
      seed: seed,
      child_count: Map.get(node, :child_count, 0) || 0,
      watcher_count: Map.get(node, :watcher_count, 0) || 0,
      comment_count: Map.get(node, :comment_count, 0) || 0,
      creator_agent_id: Map.get(node, :creator_agent_id),
      creator_address: nil,
      status: normalize_status(Map.get(node, :status)),
      summary: HomePresenter.trim_summary(Map.get(node, :summary)),
      inserted_at: graph_timestamp(Map.get(node, :inserted_at))
    }
  end

  defp enrich_graph_agents(nodes) do
    agent_directory = agent_directory_by_id(nodes)
    children_by_parent = graph_children_by_parent(nodes)

    Enum.map(nodes, fn node ->
      agent_id = Map.get(node, :creator_agent_id)
      agent_details = agent_directory |> Map.get(agent_id, %{label: nil, wallet_address: nil})

      Map.merge(node, %{
        parent_ids: if(node.parent_id, do: [node.parent_id], else: []),
        child_ids: children_by_parent |> Map.get(node.id, []) |> Enum.map(& &1.id),
        agent_id: agent_id,
        agent_label: agent_details.label,
        agent_wallet_address: agent_details.wallet_address,
        result_status: result_status_for(node),
        score: node.watcher_count || 0,
        created_at: node.inserted_at
      })
    end)
  end

  defp agent_directory_by_id(nodes) do
    agent_ids =
      nodes
      |> Enum.map(&Map.get(&1, :creator_agent_id))
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    if agent_ids == [] do
      %{}
    else
      AgentIdentity
      |> where([agent], agent.id in ^agent_ids)
      |> select([agent], %{
        id: agent.id,
        label: agent.label,
        wallet_address: agent.wallet_address
      })
      |> Repo.all()
      |> Map.new(fn %{id: id, label: label, wallet_address: wallet_address} ->
        {id,
         %{
           id: id,
           label: HomePresenter.normalize_agent_label(label, id),
           wallet_address: wallet_address
         }}
      end)
    end
  end

  defp layout_graph_nodes(nodes, seed_catalog) do
    seed_order =
      seed_catalog
      |> Enum.with_index()
      |> Map.new(fn {%{seed: seed}, index} -> {seed, index} end)

    max_depth =
      nodes
      |> Enum.map(&(&1.depth || 0))
      |> Enum.max(fn -> 0 end)
      |> max(1)

    grouped =
      nodes
      |> Enum.group_by(fn node -> {node.seed, node.depth || 0} end)
      |> Map.new(fn {{seed, depth}, grouped_nodes} ->
        ordered =
          Enum.sort_by(grouped_nodes, fn node ->
            {parse_path_segments(node), node.id}
          end)

        {{seed, depth}, ordered}
      end)

    seed_count = max(map_size(seed_order), 1)

    Enum.map(nodes, fn node ->
      depth = node.depth || 0
      seed_index = Map.get(seed_order, node.seed, map_size(seed_order))
      lane_nodes = Map.get(grouped, {node.seed, depth}, [node])
      lane_index = Enum.find_index(lane_nodes, &(&1.id == node.id)) || 0
      lane_count = max(length(lane_nodes), 1)

      cluster_center =
        if(seed_count == 1, do: 0.0, else: mixf(-0.78, 0.78, seed_index / max(seed_count - 1, 1)))

      spread = min(0.52, 0.16 + lane_count * 0.04)
      lane_norm = if(lane_count == 1, do: 0.5, else: lane_index / max(lane_count - 1, 1))
      jitter = (:erlang.phash2({node.id, node.seed, depth}, 10_000) / 10_000 - 0.5) * 0.05

      Map.merge(node, %{
        x: clampf(cluster_center + (lane_norm - 0.5) * spread + jitter, -0.92, 0.92),
        y:
          clampf(
            mixf(0.82, -0.82, depth / max_depth) +
              (seed_index - max(seed_count - 1, 0) / 2) * -0.035,
            -0.9,
            0.9
          )
      })
    end)
  end

  defp graph_edges(nodes) do
    positions = Map.new(nodes, &{&1.id, [&1.x, &1.y]})

    nodes
    |> Enum.filter(&is_integer(&1.parent_id))
    |> Enum.flat_map(fn node ->
      with source when is_list(source) <- Map.get(positions, node.parent_id),
           target when is_list(target) <- Map.get(positions, node.id) do
        [
          %{
            id: "tree:#{node.parent_id}:#{node.id}",
            source_id: node.parent_id,
            target_id: node.id,
            source: source,
            target: target,
            kind: "tree"
          }
        ]
      else
        _ -> []
      end
    end)
  end

  defp normalize_status(nil), do: "pinned"
  defp normalize_status(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_status(value) when is_binary(value), do: value

  defp result_status_for(%{kind: "null_result"}), do: "null"
  defp result_status_for(%{status: "failed_anchor"}), do: "failed"
  defp result_status_for(%{status: "pinned"}), do: "pending"
  defp result_status_for(_node), do: "success"

  defp graph_timestamp(%DateTime{} = value), do: DateTime.to_unix(value, :millisecond)

  defp graph_timestamp(%NaiveDateTime{} = value) do
    value
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix(:millisecond)
  end

  defp graph_timestamp(_value), do: nil

  defp graph_children_by_parent(nodes), do: Enum.group_by(nodes, & &1.parent_id)

  defp parse_path_segments(%{path: path, id: id}) when is_binary(path) do
    path
    |> String.split(".")
    |> Enum.map(&String.replace_prefix(&1, "n", ""))
    |> Enum.map(&Integer.parse/1)
    |> Enum.flat_map(fn
      {value, ""} -> [value]
      _ -> []
    end)
    |> case do
      [] -> [id]
      values -> values
    end
  end

  defp parse_path_segments(%{id: id}), do: [id]

  defp mixf(a, b, t), do: a + (b - a) * t
  defp clampf(value, min_value, max_value), do: value |> max(min_value) |> min(max_value)
end
