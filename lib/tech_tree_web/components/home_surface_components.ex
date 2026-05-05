defmodule TechTreeWeb.HomeSurfaceComponents do
  @moduledoc false
  use TechTreeWeb, :html

  alias TechTreeWeb.{
    HomeChatComponents,
    HomeComponentHelpers,
    HomeInstallComponents,
    HomePresenter,
    HomeStoryComponents
  }

  def regent_home_surface(assigns) do
    detail_node = assigns.grid_modal_node || assigns.selected_node

    detail_title =
      if detail_node, do: HomePresenter.display_node_title(detail_node, assigns.seed_catalog)

    detail_summary = if detail_node, do: HomePresenter.present_summary(detail_node.summary)

    assigns =
      assigns
      |> assign(:detail_node, detail_node)
      |> assign(:detail_title, detail_title)
      |> assign(:detail_summary, detail_summary)
      |> assign(:back_label, HomeComponentHelpers.terrain_back_label(assigns))
      |> assign(
        :install_agent_label,
        HomeComponentHelpers.install_agent_label(assigns.install_agent)
      )
      |> assign(:install_command, HomeComponentHelpers.install_command())
      |> assign(:start_command, HomeComponentHelpers.start_command())
      |> assign(
        :agent_handoff_command,
        HomeComponentHelpers.agent_handoff_command(assigns.install_agent)
      )

    ~H"""
    <section
      id="frontpage-regent-shell"
      class="fp-stage-shell fp-dashboard-shell rg-regent-theme-techtree"
      data-dashboard-surface="techtree-home"
    >
      <.surface
        id="techtree-home-surface"
        class="rg-regent-theme-techtree fp-terrain-surface"
        scene={@regent_scene}
        active_face={@view_mode}
        selected_target_id={@regent_selected_target_id}
        scene_version={@regent_scene_version}
        theme="techtree"
        camera_distance={28}
      >
        <:header_strip>
          <div class="fp-terrain-strip fp-dashboard-header" data-dashboard-header>
            <div class="fp-terrain-strip-brand">
              <p class="fp-terrain-kicker">TechTree</p>
              <div>
                <h1>Welcome back to TechTree.</h1>
                <p>
                  Continue the live tree, inspect BBH runs, review Science Tasks, and keep the
                  public rooms in view while the next move takes shape.
                </p>
              </div>
            </div>

            <div class="fp-terrain-strip-controls">
              <button
                :if={@back_label}
                id="frontpage-scene-back"
                type="button"
                phx-click="scene-back"
                class="rg-surface-back"
              >
                <span class="rg-surface-back-icon" aria-hidden="true">←</span>
                {@back_label}
              </button>
            </div>
          </div>

          <div class="fp-terrain-strip-meta fp-dashboard-guide-rail" data-dashboard-guide-rail>
            <div class="fp-terrain-chip-row">
              <span class="badge badge-outline font-body">Guided start</span>
              <span class="badge badge-outline font-body">
                {HomePresenter.view_mode_badge(@view_mode)}
              </span>
              <span class="badge badge-outline font-body">Start with {@install_agent_label}</span>
              <span :if={@selected_agent_id} class="badge border-0 bg-[var(--fp-accent)] text-black">
                Agent {HomePresenter.focus_agent_label(@agent_labels_by_id, @selected_agent_id)}
              </span>
            </div>
          </div>
        </:header_strip>

        <:right_rail>
          <HomeChatComponents.chat_pane
            chat_tab={@chat_tab}
            agent_messages={@agent_messages}
            human_messages={@human_messages}
            privy_app_id={@privy_app_id}
            public_chat={@public_chat}
            current_human={@current_human}
          />
        </:right_rail>

        <:chamber>
          <HomeInstallComponents.install_chamber
            install_agent={@install_agent}
            install_agent_label={@install_agent_label}
            install_command={@install_command}
            start_command={@start_command}
            agent_handoff_command={@agent_handoff_command}
          />
        </:chamber>

        <:ledger>
          <HomeStoryComponents.branch_ledger
            detail_node={@detail_node}
            detail_title={@detail_title}
            detail_summary={@detail_summary}
            seed_catalog={@seed_catalog}
            subtree_root_id={@subtree_root_id}
            subtree_mode={@subtree_mode}
            grid_modal_node={@grid_modal_node}
            view_mode={@view_mode}
            dev_dataset_toggle?={@dev_dataset_toggle?}
            data_mode={@data_mode}
            node_query={@node_query}
            node_matches={@node_matches}
            graph_agent_matches={@graph_agent_matches}
            selected_agent_id={@selected_agent_id}
            graph_meta={@graph_meta}
            grid_view_depth={@grid_view_depth}
            grid_view_key={@grid_view_key}
            install_agent_label={@install_agent_label}
            agent_handoff_command={@agent_handoff_command}
          />
        </:ledger>
      </.surface>
    </section>
    """
  end
end
