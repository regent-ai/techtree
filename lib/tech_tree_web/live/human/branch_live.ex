defmodule TechTreeWeb.Human.BranchLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.HumanComponents

  alias TechTree.HumanUX
  alias TechTree.PublicSite
  alias TechTreeWeb.{HumanComponents, PublicSiteComponents}

  @impl true
  def mount(%{"seed" => seed}, _session, socket) do
    page = HumanUX.seed_page(seed)

    {:ok,
     socket
     |> assign(:seed, seed)
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:known_seed?, page.known_seed?)
     |> assign(:branches, page.branches)
     |> assign(:graph_nodes, page.graph_nodes)
     |> assign(:view, :branch)
     |> assign(:page_title, "#{seed}")}
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
      id="tree-seed-page"
      class="hu-page"
      phx-hook="PublicSiteMotion"
      data-motion-scope="branch"
      data-motion-view={Atom.to_string(@view)}
    >
      <div class="hu-shell">
        <PublicSiteComponents.public_topbar current={:tree} ios_app_url={@ios_app_url} />

        <.human_header
          kicker="Explore Tree"
          title={"#{@seed}"}
          subtitle="Inspect active branches in one topic, switch between branch and graph view, and open any visible node."
        >
          <:actions>
            <.link id="seed-back-link" navigate={~p"/tree"} class="hu-ghost-link">
              All seeds
            </.link>
            <.link
              id="branch-view-toggle"
              patch={~p"/tree/seed/#{@seed}"}
              class={HumanComponents.toggle_class(@view == :branch)}
            >
              Branch
            </.link>
            <.link
              id="graph-view-toggle"
              patch={~p"/tree/seed/#{@seed}?view=graph"}
              class={HumanComponents.toggle_class(@view == :graph)}
            >
              Graph
            </.link>
          </:actions>
        </.human_header>

        <%= if @known_seed? do %>
          <%= if @view == :graph do %>
            <.human_section id="seed-graph" title="Graph view">
              <%= if @graph_nodes == [] do %>
                <.empty_state message="No graph data is available for this seed yet." />
              <% else %>
                <ol id="seed-graph-canvas" class="hu-graph-list">
                  <%= for node <- @graph_nodes do %>
                    <li
                      id={"graph-node-#{node.id}"}
                      class="hu-graph-node"
                      style={"--hu-depth: #{node.depth}"}
                      data-motion="graph-node"
                    >
                      <.link navigate={~p"/tree/node/#{node.id}"} class="hu-graph-link">
                        <span class="hu-graph-kind">{HumanComponents.kind(node.kind)}</span>
                        <span class="hu-graph-title">{node.title}</span>
                        <span class="hu-graph-meta">
                          {node.child_count} children · {node.watcher_count} watchers
                        </span>
                      </.link>
                    </li>
                  <% end %>
                </ol>
              <% end %>
            </.human_section>
          <% else %>
            <.human_section id="seed-branches" title="Active branches">
              <%= if @branches == [] do %>
                <.empty_state message="No active branches found for this seed yet." />
              <% else %>
                <div id="seed-branch-list" class="hu-branch-list">
                  <%= for node <- @branches do %>
                    <article id={"branch-node-#{node.id}"} class="hu-branch-card" data-motion="reveal">
                      <div class="hu-branch-head">
                        <p class="hu-branch-title">{node.title}</p>
                        <span class="hu-count-chip">{HumanComponents.kind(node.kind)}</span>
                      </div>

                      <div :if={HumanComponents.autoskill?(node)} class="hu-autoskill-row">
                        <span class="hu-autoskill-chip">
                          {HumanComponents.autoskill_flavor_label(node)}
                        </span>
                        <span :if={HumanComponents.autoskill_mode_label(node)} class="hu-list-meta">
                          {HumanComponents.autoskill_mode_label(node)}
                        </span>
                        <span :if={HumanComponents.autoskill_score_summary(node)} class="hu-list-meta">
                          {HumanComponents.autoskill_score_summary(node)}
                        </span>
                        <span
                          :if={HumanComponents.autoskill_listing_summary(node)}
                          class="hu-list-meta"
                        >
                          {HumanComponents.autoskill_listing_summary(node)}
                        </span>
                      </div>

                      <p class="hu-branch-summary">
                        {HumanComponents.present(node.summary, "No summary available.")}
                      </p>

                      <dl class="hu-stat-grid">
                        <.human_stat label="Children" value={Integer.to_string(node.child_count)} />
                        <.human_stat label="Comments" value={Integer.to_string(node.comment_count)} />
                        <.human_stat label="Watchers" value={Integer.to_string(node.watcher_count)} />
                      </dl>

                      <.link navigate={~p"/tree/node/#{node.id}"} class="hu-primary-link">
                        Open node
                      </.link>
                    </article>
                  <% end %>
                </div>
              <% end %>
            </.human_section>
          <% end %>
        <% else %>
          <.human_section id="seed-not-found" title="Unknown seed">
            <.empty_state message="This seed is not part of the supported root set." />
          </.human_section>
        <% end %>
      </div>
    </main>
    """
  end
end
