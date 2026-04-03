defmodule TechTreeWeb.HomeLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.Chatbox
  alias TechTreeWeb.HomeLive.{Dataset, State}
  alias TechTreeWeb.{HomeComponents, HomePresenter, HomeRegentScene}

  @dev_dataset_toggle? Application.compile_env(:tech_tree, :dev_routes, false)
  @default_view_mode "graph"
  @default_data_mode "live"

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
      :ok = Chatbox.subscribe()
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
     |> assign(:agent_panel_open?, true)
     |> assign(:human_panel_open?, true)
     |> assign(:intro_open?, true)
     |> assign_dataset(@default_data_mode)
     |> assign_public_chatbox_panels()
     |> assign(:page_title, "TechTree")}
  end

  @impl true
  def handle_info({:chatbox_event, _envelope}, socket) do
    {:noreply, assign_public_chatbox_panels(socket)}
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
    {:noreply, assign(socket, State.toggle_panel(panel, socket.assigns))}
  end

  @impl true
  def handle_event("set-view-mode", %{"mode" => mode}, socket) do
    next_mode = State.next_view_mode(mode, socket.assigns.view_mode)
    {:noreply, assign_and_sync_scene(socket, :view_mode, next_mode)}
  end

  @impl true
  def handle_event("set-data-mode", %{"mode" => mode}, socket) do
    {:noreply, assign_dataset(socket, mode)}
  end

  @impl true
  def handle_event("select-node", %{"node_id" => node_id}, socket) do
    {:noreply, select_node_and_sync(socket, node_id)}
  end

  @impl true
  def handle_event("focus-node", %{"node_id" => node_id}, socket),
    do: {:noreply, select_node_and_sync(socket, node_id)}

  @impl true
  def handle_event("focus-agent", params, socket) do
    {:noreply,
     assign_and_sync_scene(
       socket,
       State.focus_agent(
         Map.get(params, "agent_id"),
         socket.assigns.selected_agent_id,
         socket.assigns.agent_focus_options
       )
     )}
  end

  @impl true
  def handle_event("update-agent-query", %{"agent_query" => query}, socket) do
    {:noreply,
     assign(socket, State.update_agent_query(query, socket.assigns.agent_focus_options))}
  end

  @impl true
  def handle_event("update-node-query", %{"node_query" => query}, socket) do
    {:noreply,
     assign(
       socket,
       State.update_node_query(query, socket.assigns.graph_nodes, socket.assigns.seed_catalog)
     )}
  end

  @impl true
  def handle_event("focus-agent-query", %{"agent_query" => query}, socket) do
    {:noreply,
     assign_and_sync_scene(
       socket,
       State.focus_agent_query(query, socket.assigns.agent_focus_options)
     )}
  end

  @impl true
  def handle_event("focus-node-query", %{"node_query" => query}, socket) do
    {:noreply,
     assign_and_sync_scene(
       socket,
       State.focus_node_query(query, socket.assigns.graph_nodes, socket.assigns.seed_catalog)
     )}
  end

  @impl true
  def handle_event("focus-subtree", params, socket) do
    {:noreply,
     assign_and_sync_scene(
       socket,
       State.focus_subtree(
         params,
         socket.assigns.selected_node_id,
         socket.assigns.subtree_root_id,
         socket.assigns.subtree_mode
       )
     )}
  end

  @impl true
  def handle_event("toggle-null-results", _params, socket) do
    {:noreply, assign_and_sync_scene(socket, State.toggle_show_null_results(socket.assigns))}
  end

  @impl true
  def handle_event("filter-null-results", _params, socket) do
    {:noreply, assign_and_sync_scene(socket, State.toggle_filter_null_results(socket.assigns))}
  end

  @impl true
  def handle_event("clear-graph-focus", _params, socket) do
    {:noreply,
     assign_and_sync_scene(
       socket,
       State.clear_graph_focus(socket.assigns.agent_focus_options)
     )}
  end

  @impl true
  def handle_event("scene-back", _params, socket) do
    cond do
      socket.assigns.grid_modal_node ->
        {:noreply, socket |> assign_grid_modal(nil) |> sync_regent_scene()}

      socket.assigns.grid_view_stack != [] ->
        handle_event("return-grid-level", %{}, socket)

      socket.assigns.node_focus_target_id ->
        {:noreply, assign_and_sync_scene(socket, State.clear_node_focus(socket.assigns))}

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open-grid-node", params, socket) do
    case params |> node_id_param() |> parse_node_id() do
      nil ->
        {:noreply, socket}

      parsed_node_id ->
        {:noreply,
         socket
         |> select_node_and_sync(parsed_node_id)
         |> assign_grid_modal(parsed_node_id)
         |> sync_regent_scene()}
    end
  end

  @impl true
  def handle_event("regent:node_select", %{"face_id" => face_id, "meta" => meta}, socket) do
    action =
      meta["face_action"] ||
        if(face_id == "grid", do: "open-grid-node", else: "select-node")

    node_id = meta["node_id"] || Map.get(meta, :node_id)

    case action do
      "return-grid-level" ->
        handle_event("return-grid-level", %{}, socket)

      "open-grid-node" ->
        handle_event("open-grid-node", %{"node_id" => node_id}, socket)

      _ ->
        handle_event("select-node", %{"node_id" => node_id}, socket)
    end
  end

  @impl true
  def handle_event("regent:node_hover", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("regent:surface_ready", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("regent:surface_error", _params, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "The Regent homepage surface failed to render in this browser session."
     )}
  end

  @impl true
  def handle_event("close-grid-node-modal", _params, socket) do
    {:noreply, socket |> assign_grid_modal(nil) |> sync_regent_scene()}
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
           |> select_node_and_sync(parsed_node_id)
           |> assign_grid_modal(nil)
           |> assign_grid_view(socket.assigns.grid_view_stack ++ [parsed_node_id])
           |> sync_regent_scene()}
        else
          {:noreply, socket |> assign_grid_modal(nil) |> sync_regent_scene()}
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
     |> assign_grid_view(next_stack)
     |> sync_regent_scene()}
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

  defp assign_dataset(socket, requested_mode) do
    socket
    |> assign(Dataset.build(requested_mode, @dev_dataset_toggle?))
    |> assign_grid_modal(nil)
    |> assign_grid_view([])
    |> sync_regent_scene()
  end

  defp assign_public_chatbox_panels(socket) do
    %{messages: messages} = Chatbox.list_public_messages(%{"limit" => "24"})

    assign(socket, %{
      agent_messages: HomePresenter.build_public_panel_messages(messages, :agent),
      human_messages: HomePresenter.build_public_panel_messages(messages, :human)
    })
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
      grid_child_counts: view_child_counts
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

  defp assign_and_sync_scene(socket, updates) when is_map(updates) do
    socket
    |> assign(updates)
    |> sync_regent_scene()
  end

  defp assign_and_sync_scene(socket, key, value) do
    socket
    |> assign(key, value)
    |> sync_regent_scene()
  end

  defp select_node_and_sync(socket, node_id) do
    assign_and_sync_scene(
      socket,
      State.select_node(node_id, socket.assigns.graph_nodes, socket.assigns.selected_node_id)
    )
  end

  defp sync_regent_scene(socket) do
    next_version = (socket.assigns[:regent_scene_version] || 0) + 1

    scene =
      socket.assigns
      |> Map.put(:regent_scene_version, next_version)
      |> HomeRegentScene.build()

    selected_node_id =
      cond do
        socket.assigns.grid_modal_node ->
          Integer.to_string(socket.assigns.grid_modal_node.id)

        is_binary(socket.assigns.node_focus_target_id) ->
          socket.assigns.node_focus_target_id

        true ->
          nil
      end

    socket
    |> assign(:regent_scene_version, next_version)
    |> assign(:regent_scene, scene)
    |> assign(:regent_selected_target_id, selected_node_id)
  end
end
