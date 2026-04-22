defmodule TechTreeWeb.LandingLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.PublicSite
  alias TechTreeWeb.LandingComponents

  @default_agent "openclaw"

  @impl true
  def mount(params, _session, socket) do
    selected_agent = PublicSite.find_install_agent(params["agent"] || @default_agent)
    rooms = PublicSite.room_panels(12)

    {:ok,
     socket
     |> assign(:page_title, "TechTree")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:install_command, PublicSite.install_command())
     |> assign(:start_command, PublicSite.start_command())
     |> assign(:install_agents, PublicSite.install_agents())
     |> assign(:selected_agent, selected_agent)
     |> assign(:activity_rows, PublicSite.latest_agent_activity_rows(10))
     |> assign(:recent_nodes, PublicSite.recent_node_cards(3))
     |> assign(:popular_nodes, PublicSite.popular_node_cards(3))
     |> assign(:featured_branches, PublicSite.featured_branch_cards(4))
     |> assign(:notebooks, PublicSite.notebook_cards(3))
     |> assign(:human_messages, rooms.human)
     |> assign(:agent_messages, rooms.agent)
     |> assign(:learn_topics, PublicSite.learn_topics())}
  end

  @impl true
  def render(assigns), do: LandingComponents.landing_page(assigns)

  @impl true
  def handle_event("set-agent", %{"agent" => agent_id}, socket) do
    {:noreply, assign(socket, :selected_agent, PublicSite.find_install_agent(agent_id))}
  end
end
