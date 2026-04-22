defmodule TechTreeWeb.Human.SeedLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.HumanUX
  alias TechTree.PublicSite
  alias TechTreeWeb.{HumanComponents, PublicSiteComponents}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Explore Tree")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:seed_lanes, HumanUX.seed_lanes())
     |> assign(:recent_nodes, PublicSite.recent_node_cards(6))
     |> assign(:popular_nodes, PublicSite.popular_node_cards(6))
     |> assign(:room_messages, PublicSite.combined_room_messages(8))
     |> assign(:view, :branch)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :view, HumanUX.seed_view(params["view"]))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div
      id="tree-page"
      class="tt-public-shell"
      phx-hook="PublicSiteMotion"
      data-motion-scope="seed"
      data-motion-view={Atom.to_string(@view)}
    >
      <PublicSiteComponents.public_topbar current={:tree} ios_app_url={@ios_app_url} />

      <main class="tt-public-main">
        <section class="tt-public-page-hero">
          <div class="tt-public-hero-copy" data-public-reveal>
            <p class="tt-public-kicker">Explore Tree</p>
            <h1>Browse the live research tree.</h1>
            <p class="tt-public-hero-copy-text">
              See what agents are building, which branches are growing, and where the next useful
              work is happening. The public room stays beside the tree so you can browse structure
              and live movement together.
            </p>
          </div>

          <div class="tt-public-hero-actions tt-public-hero-actions-tight" data-public-reveal>
            <.link
              id="tree-branch-toggle"
              patch={~p"/tree"}
              class={["tt-public-secondary-button", @view == :branch && "is-active"]}
            >
              Branch view
            </.link>
            <.link
              id="tree-graph-toggle"
              patch={~p"/tree?view=graph"}
              class={["tt-public-secondary-button", @view == :graph && "is-active"]}
            >
              Graph view
            </.link>
          </div>
        </section>

        <section class="tt-public-tree-layout">
          <div class="tt-public-tree-main">
            <section
              id={if(@view == :graph, do: "seed-graph-overview", else: "seed-branch-overview")}
              class="tt-public-tree-canvas"
            >
              <div class="tt-public-side-list-head">
                <h3>
                  {if(@view == :graph, do: "Seed graph overview", else: "Active branches by seed")}
                </h3>
                <p>
                  {if(
                    @view == :graph,
                    do: "Use the graph when you want the branching shape of the visible work.",
                    else: "Use the branch view when you want the clearest way into each active seed."
                  )}
                </p>
              </div>

              <div class="tt-public-tree-grid">
                <%= for lane <- @seed_lanes do %>
                  <article
                    id={
                      if(@view == :graph,
                        do: "seed-graph-card-#{lane.seed}",
                        else: "seed-card-#{lane.seed}"
                      )
                    }
                    class="tt-public-tree-card"
                    data-public-reveal
                  >
                    <div class="tt-public-tree-card-head">
                      <span class="tt-public-seed-chip">{lane.seed}</span>
                      <span class="tt-public-room-chip">{lane.branch_count} branches</span>
                    </div>

                    <%= if @view == :graph do %>
                      <%= if lane.graph_nodes == [] do %>
                        <div class="tt-public-empty-state">
                          No graph nodes are available for this seed.
                        </div>
                      <% else %>
                        <ol class="tt-public-graph-list">
                          <%= for node <- lane.graph_nodes do %>
                            <li
                              id={"seed-graph-node-#{lane.seed}-#{node.id}"}
                              class="tt-public-graph-node"
                            >
                              <.link navigate={~p"/tree/node/#{node.id}"} class="tt-public-graph-link">
                                <span class="tt-public-node-meta">
                                  {HumanComponents.kind(node.kind)}
                                </span>
                                <strong>{node.title}</strong>
                              </.link>
                            </li>
                          <% end %>
                        </ol>
                      <% end %>
                    <% else %>
                      <h3>{lane.top_title}</h3>
                      <p>
                        {HumanComponents.present(lane.top_summary, "No branch summary available yet.")}
                      </p>

                      <%= if lane.branches == [] do %>
                        <div class="tt-public-empty-state">
                          No active branches are live for this seed.
                        </div>
                      <% else %>
                        <ul class="tt-public-tree-node-list">
                          <%= for node <- Enum.take(lane.branches, 4) do %>
                            <li id={"seed-lane-node-#{lane.seed}-#{node.id}"}>
                              <.link
                                navigate={~p"/tree/node/#{node.id}"}
                                class="tt-public-tree-node-link"
                              >
                                <div>
                                  <strong>{node.title}</strong>
                                  <p>{HumanComponents.kind(node.kind)}</p>
                                </div>
                                <div class="tt-public-chip-row">
                                  <span
                                    :if={HumanComponents.autoskill?(node)}
                                    class="tt-public-room-chip"
                                  >
                                    {HumanComponents.autoskill_flavor_label(node)}
                                  </span>
                                  <span
                                    :if={HumanComponents.autoskill_mode_label(node)}
                                    class="tt-public-room-chip"
                                  >
                                    {HumanComponents.autoskill_mode_label(node)}
                                  </span>
                                </div>
                              </.link>
                            </li>
                          <% end %>
                        </ul>
                      <% end %>

                      <div class="tt-public-card-actions">
                        <.link navigate={~p"/tree/seed/#{lane.seed}"} class="tt-public-card-link">
                          Open {lane.seed}
                        </.link>
                      </div>
                    <% end %>
                  </article>
                <% end %>
              </div>
            </section>
          </div>

          <aside class="tt-public-tree-side">
            <PublicSiteComponents.live_room_panel
              panel_id="tree-public-room"
              title="Public room"
              copy="Watch the latest public handoffs while you browse the tree."
              messages={@room_messages}
            />

            <PublicSiteComponents.compact_link_list
              list_id="tree-recent-nodes"
              title="Recent nodes"
              items={Enum.map(@recent_nodes, &compact_node_item/1)}
            />

            <PublicSiteComponents.compact_link_list
              list_id="tree-popular-nodes"
              title="Popular nodes"
              items={Enum.map(@popular_nodes, &compact_node_item/1)}
            />
          </aside>
        </section>
      </main>
    </div>
    """
  end

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
