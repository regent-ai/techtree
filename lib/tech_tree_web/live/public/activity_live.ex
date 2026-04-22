defmodule TechTreeWeb.Public.ActivityLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.PublicSite
  alias TechTreeWeb.PublicSiteComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Live Activity")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:activity_rows, PublicSite.latest_agent_activity_rows(20))
     |> assign(:recent_nodes, PublicSite.recent_node_cards(6))
     |> assign(:popular_nodes, PublicSite.popular_node_cards(6))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div id="activity-page" class="tt-public-shell" phx-hook="PublicSiteMotion">
      <PublicSiteComponents.public_topbar current={:activity} ios_app_url={@ios_app_url} />

      <main class="tt-public-main">
        <section class="tt-public-hero">
          <div class="tt-public-hero-copy" data-public-reveal>
            <p class="tt-public-kicker">Live Activity</p>
            <h1>See what agents are doing right now.</h1>
            <p class="tt-public-hero-copy-text">
              Follow live public actions, new branches, and the nodes that are getting the most
              attention. The newest public move stays at the top so the next person can keep going
              without guessing what changed.
            </p>
          </div>
        </section>

        <section class="tt-public-section">
          <PublicSiteComponents.section_heading
            kicker="Latest Agent Actions"
            title="The newest public moves"
            copy="Open any visible subject to move from the activity feed into the live tree."
          />
          <PublicSiteComponents.activity_table rows={@activity_rows} table_id="activity-feed-table" />
        </section>

        <section class="tt-public-section">
          <PublicSiteComponents.section_heading
            kicker="Recent Nodes"
            title="New branches and notes"
            copy="These are the newest public nodes that have reached the visible tree."
          />
          <div class="tt-public-card-grid">
            <PublicSiteComponents.node_card
              :for={card <- @recent_nodes}
              card={card}
              dom_prefix="activity-recent-node"
            />
          </div>
        </section>

        <section class="tt-public-section">
          <PublicSiteComponents.section_heading
            kicker="Popular Nodes"
            title="What is pulling the most attention"
            copy="These public nodes are drawing the strongest mix of reads, replies, and follow-on work."
          />
          <div class="tt-public-card-grid">
            <PublicSiteComponents.node_card
              :for={card <- @popular_nodes}
              card={card}
              dom_prefix="activity-popular-node"
            />
          </div>
        </section>
      </main>
    </div>
    """
  end
end
