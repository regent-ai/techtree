defmodule TechTreeWeb.HomeLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.{Accounts, HomeGraph, PublicChat}
  alias TechTreeWeb.HomeLive.State
  alias TechTreeWeb.{HomeComponents, HomePresenter, HomeRegentScene}

  @dev_dataset_toggle? Application.compile_env(:tech_tree, :dev_routes, false)
  @default_view_mode "graph"
  @default_data_mode "live"
  @default_install_agent "openclaw"
  @default_chat_tab "human"

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      :ok = PublicChat.subscribe()
    end

    {:ok,
     socket
     |> assign(:current_human, current_human(session))
     |> assign(:dev_dataset_toggle?, @dev_dataset_toggle?)
     |> assign(
       :privy_app_id,
       Keyword.get(Application.get_env(:tech_tree, :privy, []), :app_id, "")
     )
     |> assign(:home_unicorn_hero, home_unicorn_hero_config())
     |> assign(:view_mode, @default_view_mode)
     |> assign(:install_agent, @default_install_agent)
     |> assign(:chat_tab, @default_chat_tab)
     |> assign_dataset(@default_data_mode)
     |> assign_public_chatbox_panels()
     |> assign(:page_title, "TechTree")}
  end

  @impl true
  def handle_info({:public_site_event, %{event: event}}, socket)
      when event in [:xmtp_room_message, :xmtp_room_membership] do
    {:noreply, assign_public_chatbox_panels(socket)}
  end

  def handle_info({:public_site_event, _payload}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("frontpage_chat_join", _params, socket) do
    case PublicChat.request_join(socket.assigns[:current_human]) do
      {:ok, panel} ->
        {:noreply, assign_public_chatbox_panels(socket, panel)}

      {:error, reason} ->
        {:noreply, put_public_chatbox_status(socket, PublicChat.reason_message(reason))}
    end
  end

  @impl true
  def handle_event("frontpage_chat_send", %{"body" => body}, socket) do
    case PublicChat.send_message(socket.assigns[:current_human], body) do
      {:ok, panel} ->
        {:noreply, assign_public_chatbox_panels(socket, panel)}

      {:error, reason} ->
        {:noreply, put_public_chatbox_status(socket, PublicChat.reason_message(reason))}
    end
  end

  @impl true
  def handle_event("frontpage_chat_heartbeat", _params, socket) do
    :ok = PublicChat.heartbeat(socket.assigns[:current_human])
    {:noreply, socket}
  end

  @impl true
  def handle_event("set-install-agent", %{"agent" => agent}, socket) do
    {:noreply,
     assign(socket, :install_agent, normalize_install_agent(agent, socket.assigns.install_agent))}
  end

  @impl true
  def handle_event("set-chat-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :chat_tab, normalize_chat_tab(tab, socket.assigns.chat_tab))}
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

  defp home_unicorn_hero_config do
    cfg = Application.get_env(:tech_tree, :home_unicorn_hero, [])
    project_id = Keyword.get(cfg, :project_id, "")
    script_url = Keyword.get(cfg, :script_url, "")

    %{
      enabled?:
        Keyword.get(cfg, :enabled?, false) && present?(project_id) && present?(script_url),
      project_id: project_id,
      script_url: script_url
    }
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp assign_dataset(socket, requested_mode) do
    socket
    |> assign(
      HomeGraph.build(requested_mode, @dev_dataset_toggle?)
      |> HomePresenter.home_graph_assigns()
    )
    |> assign_grid_modal(nil)
    |> assign_grid_view([])
    |> sync_regent_scene()
  end

  defp current_human(%{"privy_user_id" => privy_user_id}) when is_binary(privy_user_id) do
    Accounts.get_human_by_privy_id(privy_user_id)
  end

  defp current_human(%{privy_user_id: privy_user_id}) when is_binary(privy_user_id) do
    Accounts.get_human_by_privy_id(privy_user_id)
  end

  defp current_human(_session), do: nil

  defp assign_public_chatbox_panels(socket, panel \\ nil) do
    panel = panel || PublicChat.room_panel(socket.assigns[:current_human])
    messages = PublicChat.split_messages(panel)

    assign(socket, %{
      public_chat: panel,
      agent_messages: HomePresenter.build_shared_public_panel_messages(messages.agent),
      human_messages: HomePresenter.build_shared_public_panel_messages(messages.human)
    })
  end

  defp put_public_chatbox_status(socket, message) do
    assign(socket, :public_chat, Map.put(socket.assigns.public_chat, :status, message))
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

  defp normalize_install_agent("openclaw", _current), do: "openclaw"
  defp normalize_install_agent("hermes", _current), do: "hermes"
  defp normalize_install_agent(_agent, current), do: current

  defp normalize_chat_tab("human", _current), do: "human"
  defp normalize_chat_tab("agent", _current), do: "agent"
  defp normalize_chat_tab(_tab, current), do: current

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
