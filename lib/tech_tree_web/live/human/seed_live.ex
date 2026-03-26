defmodule TechTreeWeb.Human.SeedLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.HumanComponents

  alias TechTree.HumanUX
  alias TechTreeWeb.HumanComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Human Branches")
     |> assign(:seed_lanes, HumanUX.seed_lanes())
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
    <main
      id="human-seed-page"
      class="hu-page"
      phx-hook="HumanMotion"
      data-motion-scope="seed"
      data-motion-view={Atom.to_string(@view)}
    >
      <div class="hu-shell">
        <.human_header
          kicker="Human UX"
          title="Branch-first navigation"
          subtitle="Default to branch lanes. Toggle graph only when you need a tree scan."
        >
          <:actions>
            <.link
              id="home-branch-toggle"
              patch={~p"/human"}
              class={HumanComponents.toggle_class(@view == :branch)}
            >
              Branch
            </.link>
            <.link
              id="home-graph-toggle"
              patch={~p"/human?view=graph"}
              class={HumanComponents.toggle_class(@view == :graph)}
            >
              Graph
            </.link>
          </:actions>
        </.human_header>

        <%= if @view == :graph do %>
          <.human_section id="seed-graph-overview" title="Seed graph overview">
            <div class="hu-seed-grid">
              <%= for lane <- @seed_lanes do %>
                <article id={"seed-graph-card-#{lane.seed}"} class="hu-seed-card" data-motion="reveal">
                  <div class="hu-seed-card-head">
                    <p class="hu-seed-name">{lane.seed}</p>
                    <span class="hu-count-chip">{lane.branch_count} branches</span>
                  </div>

                  <%= if lane.graph_nodes == [] do %>
                    <.empty_state message="No graph nodes are available for this seed." />
                  <% else %>
                    <ol class="hu-graph-list">
                      <%= for node <- lane.graph_nodes do %>
                        <li
                          id={"seed-graph-node-#{lane.seed}-#{node.id}"}
                          class="hu-graph-node"
                          style={"--hu-depth: #{node.depth}"}
                          data-motion="graph-node"
                        >
                          <.link navigate={~p"/node/#{node.id}"} class="hu-graph-link">
                            <span class="hu-graph-kind">{HumanComponents.kind(node.kind)}</span>
                            <span class="hu-graph-title">{node.title}</span>
                          </.link>
                        </li>
                      <% end %>
                    </ol>
                  <% end %>
                </article>
              <% end %>
            </div>
          </.human_section>
        <% else %>
          <.human_section id="seed-branch-overview" title="Active branches by seed">
            <div class="hu-seed-grid">
              <%= for lane <- @seed_lanes do %>
                <article id={"seed-card-#{lane.seed}"} class="hu-seed-card" data-motion="reveal">
                  <div class="hu-seed-card-head">
                    <p class="hu-seed-name">{lane.seed}</p>
                    <span class="hu-count-chip">{lane.branch_count} branches</span>
                  </div>

                  <p class="hu-seed-top">{lane.top_title}</p>
                  <p class="hu-seed-summary">
                    {HumanComponents.present(lane.top_summary, "No branch summary available yet.")}
                  </p>

                  <%= if lane.branches == [] do %>
                    <.empty_state message="No active branches are live for this seed." />
                  <% else %>
                    <ul class="hu-list">
                      <%= for node <- Enum.take(lane.branches, 4) do %>
                        <li id={"seed-lane-node-#{lane.seed}-#{node.id}"}>
                          <div class="hu-list-link hu-list-link-stack">
                            <.link navigate={~p"/node/#{node.id}"} class="hu-inline-link">
                              {node.title}
                            </.link>
                            <span class="hu-list-meta">{HumanComponents.kind(node.kind)}</span>
                            <span :if={HumanComponents.autoskill?(node)} class="hu-autoskill-chip">
                              {HumanComponents.autoskill_flavor_label(node)}
                            </span>
                            <span
                              :if={HumanComponents.autoskill_mode_label(node)}
                              class="hu-list-meta"
                            >
                              {HumanComponents.autoskill_mode_label(node)}
                            </span>
                            <span
                              :if={HumanComponents.autoskill_score_summary(node)}
                              class="hu-list-meta"
                            >
                              {HumanComponents.autoskill_score_summary(node)}
                            </span>
                            <span
                              :if={HumanComponents.autoskill_listing_summary(node)}
                              class="hu-list-meta"
                            >
                              {HumanComponents.autoskill_listing_summary(node)}
                            </span>
                          </div>
                        </li>
                      <% end %>
                    </ul>
                  <% end %>

                  <.link navigate={~p"/seed/#{lane.seed}"} class="hu-primary-link">
                    Open {lane.seed}
                  </.link>
                </article>
              <% end %>
            </div>
          </.human_section>
        <% end %>
      </div>
    </main>
    """
  end
end
