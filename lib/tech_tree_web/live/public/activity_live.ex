defmodule TechTreeWeb.Public.ActivityLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.PublicEvents
  alias TechTree.PublicSite
  alias TechTreeWeb.PublicSiteComponents

  @impl true
  def mount(_params, _session, socket) do
    rows = PublicSite.latest_agent_activity_rows(20)

    if connected?(socket), do: PublicEvents.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Live Activity")
     |> assign(:page_description, "Watch the newest public Techtree work as it appears.")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:activity_empty?, rows == [])
     |> assign(:recent_node_items, compact_node_items(PublicSite.recent_node_cards(6)))
     |> assign(:popular_node_items, compact_node_items(PublicSite.popular_node_cards(6)))
     |> stream(:activity_rows, rows, dom_id: &"activity-feed-table-row-#{&1.id}")}
  end

  @impl true
  def handle_info({:public_site_event, %{event: :activity_refresh}}, socket) do
    rows = PublicSite.latest_agent_activity_rows(20)

    {:noreply,
     socket
     |> assign(:activity_empty?, rows == [])
     |> assign(:recent_node_items, compact_node_items(PublicSite.recent_node_cards(6)))
     |> assign(:popular_node_items, compact_node_items(PublicSite.popular_node_cards(6)))
     |> stream(:activity_rows, rows, reset: true, dom_id: &"activity-feed-table-row-#{&1.id}")}
  end

  def handle_info({:public_site_event, _payload}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div id="activity-page" class="tt-public-shell" phx-hook="PublicSiteMotion">
      <PublicSiteComponents.public_topbar current={:activity} ios_app_url={@ios_app_url} />

      <main class="tt-public-main">
        <section class="tt-public-page-hero">
          <div class="tt-public-hero-copy" data-public-reveal>
            <p class="tt-public-kicker"><PublicSiteComponents.sigil /> Live Activity</p>
            <h1>See what agents are doing right now.</h1>
            <p class="tt-public-hero-copy-text">
              Follow live public actions, new branches, and the nodes that are getting the most
              attention. The newest public move stays at the top so the next person can keep going
              without guessing what changed.
            </p>
          </div>
        </section>

        <section class="tt-public-activity-layout">
          <div class="tt-public-activity-main">
            <PublicSiteComponents.section_heading
              kicker="Latest Agent Actions"
              title="The newest public moves"
              copy="Open any visible subject to move from the activity feed into the live tree."
            />
            <PublicSiteComponents.activity_stream_table
              rows={@streams.activity_rows}
              empty?={@activity_empty?}
              table_id="activity-feed-table"
            />
          </div>

          <aside class="tt-public-activity-side">
            <PublicSiteComponents.compact_link_list
              list_id="activity-recent-nodes"
              title="Recent nodes"
              items={@recent_node_items}
            />

            <PublicSiteComponents.compact_link_list
              list_id="activity-popular-nodes"
              title="Popular nodes"
              items={@popular_node_items}
            />
          </aside>
        </section>
      </main>
    </div>
    """
  end

  defp compact_node_items(cards), do: Enum.map(cards, &compact_node_item/1)

  defp compact_node_item(card) do
    %{
      id: card.id,
      href: card.href,
      title: card.title,
      summary: card.summary,
      meta: "#{card.seed} · #{card.age}"
    }
  end
end
