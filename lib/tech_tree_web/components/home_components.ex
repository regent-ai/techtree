defmodule TechTreeWeb.HomeComponents do
  @moduledoc false
  use TechTreeWeb, :html

  alias TechTreeWeb.{HomeSurfaceComponents, Layouts}

  def home_page(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <.background_grid id="techtree-home-background" class="rg-regent-theme-techtree" />
    <div
      id="frontpage-home-page"
      class="fp-showcase rg-app-shell rg-regent-theme-techtree"
      data-view-mode={@view_mode}
      data-data-mode={@data_mode}
      data-chat-tab={@chat_tab}
      data-install-agent={@install_agent}
    >
      <HomeSurfaceComponents.regent_home_surface
        regent_scene={@regent_scene}
        regent_scene_version={@regent_scene_version}
        regent_selected_target_id={@regent_selected_target_id}
        seed_catalog={@seed_catalog}
        selected_node={@selected_node}
        selected_agent_id={@selected_agent_id}
        agent_labels_by_id={@agent_labels_by_id}
        graph_meta={@graph_meta}
        graph_agent_query={@graph_agent_query}
        graph_agent_matches={@graph_agent_matches}
        node_query={@node_query}
        node_matches={@node_matches}
        subtree_root_id={@subtree_root_id}
        subtree_mode={@subtree_mode}
        show_null_results?={@show_null_results?}
        filter_to_null_results?={@filter_to_null_results?}
        grid_view_depth={@grid_view_depth}
        grid_view_key={@grid_view_key}
        grid_view_parent_id={@grid_view_parent_id}
        grid_view_stack={@grid_view_stack}
        grid_modal_node={@grid_modal_node}
        node_focus_target_id={@node_focus_target_id}
        view_mode={@view_mode}
        data_mode={@data_mode}
        dev_dataset_toggle?={@dev_dataset_toggle?}
        agent_messages={@agent_messages}
        human_messages={@human_messages}
        privy_app_id={@privy_app_id}
        public_chat={@public_chat}
        current_human={@current_human}
        install_agent={@install_agent}
        chat_tab={@chat_tab}
      />
    </div>
    """
  end
end
