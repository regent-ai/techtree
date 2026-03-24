defmodule TechTreeWeb.HomeLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import Ecto.Query, only: [where: 3, select: 3]

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Trollbox
  alias TechTree.{HumanUX, Nodes, Repo}
  alias TechTreeWeb.{HomeComponents, HomePresenter}

  @dev_dataset_toggle? Application.compile_env(:tech_tree, :dev_routes, false)
  @default_view_mode "graph"
  @default_data_mode "live"
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

  @design %{
    id: "cobalt-orchard",
    label: "TechTree",
    mood: "ink orchard",
    summary:
      "Warm parchment, cobalt fields, and ink-dark graph branches framing the live public tree as the homepage.",
    layout_mode: "atlas",
    tokens: %{
      "bg" =>
        "linear-gradient(180deg, #f6efd8 0%, #f4ecd2 52%, #fbf6e6 100%), radial-gradient(circle at 22% 18%, rgba(17, 76, 167, 0.08), transparent 18%)",
      "panel" => "rgba(251, 246, 230, 0.9)",
      "panel-border" => "rgba(196, 165, 92, 0.2)",
      "stage" => "rgba(255, 249, 235, 0.95)",
      "text" => "#111216",
      "muted" => "rgba(29, 31, 37, 0.62)",
      "accent" => "#114ca7",
      "accent-soft" => "rgba(17, 76, 167, 0.12)",
      "highlight" => "#05070d",
      "chat-meta" => "rgba(49, 44, 33, 0.6)",
      "chat-neutral-bg" => "rgba(249, 243, 227, 0.92)",
      "chat-neutral-text" => "#18191d",
      "chat-agent-accent-bg" => "rgba(225, 232, 244, 0.96)",
      "chat-agent-accent-text" => "#11294d",
      "chat-human-accent-bg" => "rgba(231, 206, 137, 0.98)",
      "chat-human-accent-text" => "#15161a",
      "chat-composer-bg" => "rgba(246, 239, 221, 0.95)",
      "chat-composer-text" => "#18191d",
      "shadow" => "0 36px 96px -62px rgba(78, 60, 28, 0.32)",
      "overlay" => "rgba(20, 18, 13, 0.54)"
    },
    graph_theme: %{
      "edge" => "#0c1120",
      "node" => "#114ca7",
      "nodeAlt" => "#05070d",
      "hover" => "#fffdf6",
      "selected" => "#d4b15b",
      "background" => "#fbf5e3"
    },
    dark_tokens: %{
      "bg" =>
        "radial-gradient(circle at 18% 18%, rgba(75, 131, 209, 0.18), transparent 20%), linear-gradient(180deg, #08111f 0%, #0b1527 46%, #03060d 100%)",
      "panel" => "rgba(10, 16, 29, 0.9)",
      "panel-border" => "rgba(244, 222, 182, 0.16)",
      "stage" => "rgba(7, 12, 23, 0.94)",
      "text" => "#f7f0dc",
      "muted" => "rgba(247, 240, 220, 0.66)",
      "accent" => "#4b83d1",
      "accent-soft" => "rgba(75, 131, 209, 0.16)",
      "highlight" => "#f0d58c",
      "chat-meta" => "rgba(247, 240, 220, 0.74)",
      "chat-neutral-bg" => "rgba(11, 18, 32, 0.94)",
      "chat-neutral-text" => "#fff8ed",
      "chat-agent-accent-bg" => "rgba(24, 47, 86, 0.96)",
      "chat-agent-accent-text" => "#fff9ef",
      "chat-human-accent-bg" => "rgba(126, 105, 54, 0.98)",
      "chat-human-accent-text" => "#fffaf2",
      "chat-composer-bg" => "rgba(12, 18, 31, 0.96)",
      "chat-composer-text" => "#fff8ed",
      "shadow" => "0 36px 110px -60px rgba(0, 0, 0, 0.92)",
      "overlay" => "rgba(2, 4, 10, 0.78)"
    },
    dark_graph_theme: %{
      "edge" => "#f0d58c",
      "node" => "#4b83d1",
      "nodeAlt" => "#f7f0dc",
      "hover" => "#ffffff",
      "selected" => "#d6a94b",
      "background" => "#07111f"
    }
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :ok = Trollbox.subscribe()
    end

    {:ok,
     socket
     |> assign(:design, @design)
     |> assign(:design_style, design_style(@design))
     |> assign(:dev_dataset_toggle?, @dev_dataset_toggle?)
     |> assign(
       :privy_app_id,
       Keyword.get(Application.get_env(:tech_tree, :privy, []), :app_id, "")
     )
     |> assign(:view_mode, @default_view_mode)
     |> assign(:top_section_open?, true)
     |> assign(:agent_panel_open?, true)
     |> assign(:human_panel_open?, true)
     |> assign(:intro_open?, true)
     |> assign_dataset(@default_data_mode)
     |> assign_public_trollbox_panels()
     |> assign(:page_title, "TechTree")}
  end

  @impl true
  def handle_info({:trollbox_event, _envelope}, socket) do
    {:noreply, assign_public_trollbox_panels(socket)}
  end

  @impl true
  def handle_event("enter", _params, socket) do
    {:noreply, assign(socket, :intro_open?, false)}
  end

  @impl true
  def handle_event("reopen_intro", _params, socket) do
    {:noreply, assign(socket, :intro_open?, true)}
  end

  @impl true
  def handle_event("toggle_panel", %{"panel" => panel}, socket) do
    socket =
      case panel do
        "top" -> update(socket, :top_section_open?, &(!&1))
        "agent" -> update(socket, :agent_panel_open?, &(!&1))
        "human" -> update(socket, :human_panel_open?, &(!&1))
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("set-view-mode", %{"mode" => mode}, socket) do
    next_mode = if mode in ["graph", "grid"], do: mode, else: socket.assigns.view_mode
    {:noreply, assign(socket, :view_mode, next_mode)}
  end

  @impl true
  def handle_event("set-data-mode", %{"mode" => mode}, socket) do
    {:noreply, assign_dataset(socket, mode)}
  end

  @impl true
  def handle_event("select-node", %{"node_id" => node_id}, socket) do
    selected_node_id =
      case Integer.parse(to_string(node_id)) do
        {parsed, ""} -> parsed
        _ -> socket.assigns.selected_node_id
      end

    {:noreply,
     socket
     |> assign(:selected_node_id, selected_node_id)
     |> assign(:selected_node, selected_node(socket.assigns.graph_nodes, selected_node_id))
     |> sync_graph_focus()
     |> push_graph_focus_event()}
  end

  @impl true
  def handle_event("focus-agent", params, socket) do
    next_agent_id =
      params
      |> Map.get("agent_id")
      |> parse_optional_integer()
      |> toggle_integer_focus(socket.assigns.selected_agent_id)

    next_query =
      HomePresenter.focus_agent_input(socket.assigns.agent_focus_options, next_agent_id)

    {:noreply,
     socket
     |> assign(:selected_agent_id, next_agent_id)
     |> assign(:graph_agent_query, next_query)
     |> assign(
       :graph_agent_matches,
       HomePresenter.matching_agent_focus_options(socket.assigns.agent_focus_options, next_query)
     )
     |> sync_graph_focus()
     |> push_graph_focus_event()}
  end

  @impl true
  def handle_event("update-agent-query", %{"agent_query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:graph_agent_query, query)
     |> assign(
       :graph_agent_matches,
       HomePresenter.matching_agent_focus_options(socket.assigns.agent_focus_options, query)
     )}
  end

  @impl true
  def handle_event("focus-agent-query", %{"agent_query" => query}, socket) do
    next_agent_id =
      socket.assigns.agent_focus_options
      |> HomePresenter.resolve_agent_focus(query)
      |> case do
        nil -> nil
        option -> option.id
      end

    {:noreply,
     socket
     |> assign(:graph_agent_query, query)
     |> assign(
       :graph_agent_matches,
       HomePresenter.matching_agent_focus_options(socket.assigns.agent_focus_options, query)
     )
     |> assign(:selected_agent_id, next_agent_id)
     |> sync_graph_focus()
     |> push_graph_focus_event()}
  end

  @impl true
  def handle_event("focus-subtree", params, socket) do
    subtree_mode =
      case Map.get(params, "mode") do
        "children" -> "children"
        "descendants" -> "descendants"
        _ -> nil
      end

    subtree_root_id =
      params
      |> Map.get("node_id")
      |> parse_optional_integer()
      |> case do
        nil -> socket.assigns.selected_node_id
        parsed -> parsed
      end

    {next_root_id, next_mode} =
      cond do
        is_nil(subtree_mode) or is_nil(subtree_root_id) ->
          {nil, nil}

        socket.assigns.subtree_root_id == subtree_root_id and
            socket.assigns.subtree_mode == subtree_mode ->
          {nil, nil}

        true ->
          {subtree_root_id, subtree_mode}
      end

    {:noreply,
     socket
     |> assign(:subtree_root_id, next_root_id)
     |> assign(:subtree_mode, next_mode)
     |> sync_graph_focus()
     |> push_graph_focus_event()}
  end

  @impl true
  def handle_event("toggle-null-results", _params, socket) do
    {:noreply,
     socket
     |> update(:show_null_results?, &(!&1))
     |> sync_graph_focus()
     |> push_graph_focus_event()}
  end

  @impl true
  def handle_event("filter-null-results", _params, socket) do
    socket =
      socket
      |> update(:filter_to_null_results?, &(!&1))
      |> ensure_null_highlight_visible()
      |> sync_graph_focus()

    {:noreply, push_graph_focus_event(socket)}
  end

  @impl true
  def handle_event("clear-graph-focus", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_agent_id, nil)
     |> assign(:subtree_root_id, nil)
     |> assign(:subtree_mode, nil)
     |> assign(:show_null_results?, false)
     |> assign(:filter_to_null_results?, false)
     |> assign(:graph_agent_query, "")
     |> assign(
       :graph_agent_matches,
       HomePresenter.matching_agent_focus_options(socket.assigns.agent_focus_options, "")
     )
     |> sync_graph_focus()
     |> push_graph_focus_event()}
  end

  @impl true
  def handle_event("open-grid-node", params, socket) do
    case params |> node_id_param() |> parse_node_id() do
      nil ->
        {:noreply, socket}

      parsed_node_id ->
        {:noreply,
         socket
         |> assign(:selected_node_id, parsed_node_id)
         |> assign(:selected_node, selected_node(socket.assigns.graph_nodes, parsed_node_id))
         |> sync_graph_focus()
         |> push_graph_focus_event()
         |> assign_grid_modal(parsed_node_id)}
    end
  end

  @impl true
  def handle_event("close-grid-node-modal", _params, socket) do
    {:noreply, assign_grid_modal(socket, nil)}
  end

  @impl true
  def handle_event("drilldown-grid-node", params, socket) do
    case params |> node_id_param() |> parse_node_id() do
      nil ->
        {:noreply, socket}

      parsed_node_id ->
        child_count = Map.get(socket.assigns.grid_child_counts, parsed_node_id, 0)

        if child_count > 0 do
          {:noreply,
           socket
           |> assign(:selected_node_id, parsed_node_id)
           |> assign(:selected_node, selected_node(socket.assigns.graph_nodes, parsed_node_id))
           |> sync_graph_focus()
           |> push_graph_focus_event()
           |> assign_grid_modal(nil)
           |> assign_grid_view(socket.assigns.grid_view_stack ++ [parsed_node_id])}
        else
          {:noreply, assign_grid_modal(socket, nil)}
        end
    end
  end

  @impl true
  def handle_event("return-grid-level", _params, socket) do
    next_stack =
      socket.assigns.grid_view_stack
      |> Enum.reverse()
      |> tl_or_empty()
      |> Enum.reverse()

    {:noreply,
     socket
     |> assign_grid_modal(nil)
     |> assign_grid_view(next_stack)}
  end

  @impl true
  def render(assigns), do: HomeComponents.home_page(assigns)

  defp design_style(design) do
    [
      encode_token_group("light", design.tokens),
      encode_graph_group("light", design.graph_theme),
      encode_token_group("dark", Map.get(design, :dark_tokens, %{})),
      encode_graph_group("dark", Map.get(design, :dark_graph_theme, %{}))
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("; ")
  end

  defp encode_token_group(_mode, tokens) when tokens == %{}, do: ""

  defp encode_token_group(mode, tokens) do
    Enum.map_join(tokens, "; ", fn {key, value} ->
      "--fp-#{mode}-#{key}: #{value}"
    end)
  end

  defp encode_graph_group(_mode, tokens) when tokens == %{}, do: ""

  defp encode_graph_group(mode, tokens) do
    Enum.map_join(tokens, "; ", fn {key, value} ->
      "--fp-#{mode}-graph-#{graph_token_name(key)}: #{value}"
    end)
  end

  defp graph_token_name("nodeAlt"), do: "node-alt"
  defp graph_token_name(other), do: other

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

  defp assign_dataset(socket, requested_mode) do
    data_mode =
      case requested_mode do
        "fixture" when @dev_dataset_toggle? -> "fixture"
        _ -> "live"
      end

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

    graph_focus =
      graph_focus_payload(%{
        selected_node_id: selected_node && selected_node.id,
        selected_agent_id: nil,
        subtree_root_id: nil,
        subtree_mode: nil,
        show_null_results?: false,
        filter_to_null_results?: false
      })

    socket
    |> assign(:agent_focus_options, agent_focus_options)
    |> assign(:data_mode, data_mode)
    |> assign(:graph_nodes, graph_nodes)
    |> assign(:graph_edges, graph_edges)
    |> assign(
      :graph_payload_json,
      Jason.encode!(graph_payload(graph_nodes, graph_edges, graph_meta))
    )
    |> assign(:graph_focus_json, Jason.encode!(graph_focus))
    |> assign(:graph_meta, graph_meta)
    |> assign(:seed_catalog, seed_catalog)
    |> assign(:agent_labels_by_id, HomePresenter.agent_labels_by_id(graph_nodes))
    |> assign(:graph_agent_query, "")
    |> assign(
      :graph_agent_matches,
      HomePresenter.matching_agent_focus_options(agent_focus_options, "")
    )
    |> assign(:selected_node_id, selected_node && selected_node.id)
    |> assign(:selected_node, selected_node)
    |> assign(:selected_agent_id, nil)
    |> assign(:subtree_root_id, nil)
    |> assign(:subtree_mode, nil)
    |> assign(:show_null_results?, false)
    |> assign(:filter_to_null_results?, false)
    |> assign(:graph_node_index, Map.new(graph_nodes, &{&1.id, &1}))
    |> assign(:graph_children_by_parent, graph_children_by_parent(graph_nodes))
    |> assign_grid_modal(nil)
    |> assign_grid_view([])
  end

  defp assign_public_trollbox_panels(socket) do
    %{messages: messages} = Trollbox.list_public_messages(%{"limit" => "24"})

    socket
    |> assign(:agent_messages, HomePresenter.build_public_panel_messages(messages, :agent))
    |> assign(:human_messages, HomePresenter.build_public_panel_messages(messages, :human))
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

  defp selected_node(graph_nodes, selected_node_id) do
    Enum.find(graph_nodes, &(&1.id == selected_node_id))
  end

  defp assign_grid_view(socket, view_stack) do
    children_by_parent = socket.assigns.graph_children_by_parent
    seed_catalog = socket.assigns.seed_catalog
    view_parent_id = List.last(view_stack)

    view_nodes =
      view_parent_id
      |> then(&Map.get(children_by_parent, &1, []))
      |> Enum.sort_by(fn node ->
        {node.depth, seed_rank(seed_catalog, node.seed), parse_path_segments(node), node.id}
      end)

    view_child_counts =
      Map.new(view_nodes, &{&1.id, Map.get(children_by_parent, &1.id, []) |> length()})

    assign(socket,
      grid_view_stack: view_stack,
      grid_view_depth: length(view_stack),
      grid_view_key: grid_view_key(view_stack),
      grid_view_parent_id: view_parent_id,
      grid_view_nodes: view_nodes,
      grid_child_counts: view_child_counts,
      grid_payload_json: Jason.encode!(HomePresenter.grid_payload(view_nodes, seed_catalog))
    )
  end

  defp assign_grid_modal(socket, nil) do
    assign(socket, :grid_modal_node, nil)
  end

  defp assign_grid_modal(socket, node_id) do
    assign(socket, :grid_modal_node, Map.get(socket.assigns.graph_node_index, node_id))
  end

  defp parse_node_id(node_id) do
    case Integer.parse(to_string(node_id)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp node_id_param(params) when is_map(params) do
    Map.get(params, "node_id") || Map.get(params, "node-id")
  end

  defp tl_or_empty([]), do: []
  defp tl_or_empty([_head | tail]), do: tail

  defp grid_view_key([]), do: "seed"
  defp grid_view_key(view_stack), do: Enum.join(view_stack, ">")

  defp seed_rank(seed_catalog, seed) do
    case Enum.find_index(seed_catalog, &(&1.seed == seed)) do
      nil -> length(seed_catalog) + 1_000
      index -> index
    end
  end

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

  defp graph_payload(graph_nodes, graph_edges, graph_meta) do
    %{
      nodes: graph_nodes,
      edges: graph_edges,
      meta: %{
        revision: graph_meta.revision,
        layout_mode: @design.layout_mode
      }
    }
  end

  defp graph_focus_payload(assigns) do
    %{
      selected_node_id: assigns.selected_node_id,
      selected_agent_id: assigns.selected_agent_id,
      subtree_root_id: assigns.subtree_root_id,
      subtree_mode: assigns.subtree_mode,
      show_null_results: assigns.show_null_results?,
      filter_to_null_results: assigns.filter_to_null_results?
    }
  end

  defp sync_graph_focus(socket) do
    assign(socket, :graph_focus_json, Jason.encode!(graph_focus_payload(socket.assigns)))
  end

  defp push_graph_focus_event(socket) do
    push_event(socket, "frontpage:graph-focus", graph_focus_payload(socket.assigns))
  end

  defp ensure_null_highlight_visible(socket) do
    if socket.assigns.filter_to_null_results? do
      assign(socket, :show_null_results?, true)
    else
      socket
    end
  end

  defp parse_optional_integer(nil), do: nil

  defp parse_optional_integer(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp toggle_integer_focus(value, current) when value == current, do: nil
  defp toggle_integer_focus(value, _current), do: value

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

  defp clampf(value, min, _max) when value < min, do: min
  defp clampf(value, _min, max) when value > max, do: max
  defp clampf(value, _min, _max), do: value

  defp mixf(from, to, progress), do: from + (to - from) * progress
end
