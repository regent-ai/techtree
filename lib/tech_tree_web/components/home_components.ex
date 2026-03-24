defmodule TechTreeWeb.HomeComponents do
  @moduledoc false
  use TechTreeWeb, :html

  alias TechTreeWeb.{HomePresenter, Layouts}

  def home_page(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div
      id="frontpage-home-page"
      class="fp-showcase"
      data-intro-open={to_string(@intro_open?)}
      data-top-open={to_string(@top_section_open?)}
      data-agent-open={to_string(@agent_panel_open?)}
      data-human-open={to_string(@human_panel_open?)}
      data-view-mode={@view_mode}
      data-data-mode={@data_mode}
      phx-hook="FrontpageWindows"
      style={@design_style}
    >
      <header id="frontpage-home-briefing" class="fp-switcher-shell">
        <section class="fp-switcher card border shadow-2xl">
          <div class="card-body gap-0 p-4">
            <div class="fp-switcher-bar flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
              <div class="space-y-2">
                <div class="flex flex-wrap items-center gap-2">
                  <span class="badge badge-outline font-body">Live public frontier</span>
                  <span class="badge badge-outline font-body">
                    {HomePresenter.view_mode_badge(@view_mode)}
                  </span>
                  <span class="badge badge-outline font-body">{@design.mood}</span>
                  <span class="badge badge-outline font-body">Default light mode</span>
                </div>
                <div>
                  <p class="font-display text-lg uppercase tracking-[0.24em] text-[var(--fp-accent)]">
                    TechTree Homepage
                  </p>
                </div>
              </div>

              <div class="fp-switcher-actions flex flex-wrap items-center justify-end gap-2">
                <div class="join fp-view-toggle">
                  <button
                    id="frontpage-view-graph"
                    type="button"
                    phx-click="set-view-mode"
                    phx-value-mode="graph"
                    aria-pressed={to_string(@view_mode == "graph")}
                    class={[
                      "btn join-item btn-sm border-0",
                      if(@view_mode == "graph",
                        do: "bg-[var(--fp-accent)] text-black hover:brightness-110",
                        else:
                          "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                      )
                    ]}
                  >
                    Tree graph
                  </button>
                  <button
                    id="frontpage-view-grid"
                    type="button"
                    phx-click="set-view-mode"
                    phx-value-mode="grid"
                    aria-pressed={to_string(@view_mode == "grid")}
                    class={[
                      "btn join-item btn-sm border-0",
                      if(@view_mode == "grid",
                        do: "bg-[var(--fp-accent)] text-black hover:brightness-110",
                        else:
                          "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                      )
                    ]}
                  >
                    Infinite grid
                  </button>
                </div>
                <div :if={@dev_dataset_toggle?} class="join fp-view-toggle">
                  <button
                    id="frontpage-data-live"
                    type="button"
                    phx-click="set-data-mode"
                    phx-value-mode="live"
                    aria-pressed={to_string(@data_mode == "live")}
                    class={[
                      "btn join-item btn-sm border-0",
                      if(@data_mode == "live",
                        do: "bg-[var(--fp-accent)] text-black hover:brightness-110",
                        else:
                          "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                      )
                    ]}
                  >
                    Live data
                  </button>
                  <button
                    id="frontpage-data-fixture"
                    type="button"
                    phx-click="set-data-mode"
                    phx-value-mode="fixture"
                    aria-pressed={to_string(@data_mode == "fixture")}
                    class={[
                      "btn join-item btn-sm border-0",
                      if(@data_mode == "fixture",
                        do: "bg-[var(--fp-accent)] text-black hover:brightness-110",
                        else:
                          "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                      )
                    ]}
                  >
                    Test data
                  </button>
                </div>
                <button
                  id="frontpage-top-toggle"
                  type="button"
                  phx-click="toggle_panel"
                  phx-value-panel="top"
                  class="btn btn-sm border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                >
                  {if @top_section_open?, do: "Hide briefing", else: "Show briefing"}
                </button>
                <button
                  id="frontpage-reopen-intro"
                  type="button"
                  phx-click="reopen_intro"
                  class="btn btn-sm border-0 bg-[var(--fp-accent)] text-black hover:brightness-110"
                >
                  Reopen intro
                </button>
              </div>
            </div>

            <div class="fp-switcher-body" data-top-body="">
              <div class="mt-4 grid gap-4 xl:grid-cols-[minmax(0,1.35fr)_minmax(18rem,0.65fr)]">
                <section class="space-y-4">
                  <div class="space-y-4">
                    <div>
                      <h1 class="mt-3 text-4xl leading-none lg:text-6xl">{@design.label}</h1>
                      <p class="mt-4 max-w-3xl text-sm leading-7 text-[var(--fp-muted)] lg:text-base">
                        {@design.summary}
                      </p>
                    </div>
                  </div>

                  <div class="grid gap-4 xl:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)]">
                    <section
                      id="frontpage-selected-node"
                      class="fp-subcard card border shadow-none"
                    >
                      <div class="card-body gap-3 p-4">
                        <div class="flex flex-wrap items-center gap-2">
                          <span class="badge badge-outline font-body">
                            {HomePresenter.selected_seed(@seed_catalog, @selected_node)}
                          </span>
                          <span class="badge badge-outline font-body">
                            {HomePresenter.selected_kind(@selected_node)}
                          </span>
                          <span
                            :if={creator_address = @selected_node && @selected_node[:creator_address]}
                            class="badge badge-outline font-body"
                          >
                            {HomePresenter.short_creator_address(creator_address)}
                          </span>
                          <span
                            :if={agent_label = @selected_node && @selected_node[:agent_label]}
                            class="badge badge-outline font-body"
                          >
                            {agent_label}
                          </span>
                          <span :if={@selected_node} class="badge badge-outline font-body">
                            {@selected_node.id}
                          </span>
                        </div>
                        <%= if @selected_node do %>
                          <h2 class="text-2xl leading-tight">
                            {HomePresenter.display_node_title(@selected_node, @seed_catalog)}
                          </h2>
                          <p class="text-sm leading-7 text-[var(--fp-muted)]">
                            {HomePresenter.present_summary(@selected_node.summary)}
                          </p>
                          <div class="stats stats-vertical border border-[var(--fp-panel-border)] bg-[var(--fp-accent-soft)] shadow-none md:stats-horizontal">
                            <div class="stat px-4 py-3">
                              <div class="stat-title text-[var(--fp-muted)]">Children</div>
                              <div class="stat-value text-xl text-[var(--fp-text)]">
                                {@selected_node.child_count}
                              </div>
                            </div>
                            <div class="stat px-4 py-3">
                              <div class="stat-title text-[var(--fp-muted)]">Watchers</div>
                              <div class="stat-value text-xl text-[var(--fp-text)]">
                                {@selected_node.watcher_count}
                              </div>
                            </div>
                            <div class="stat px-4 py-3">
                              <div class="stat-title text-[var(--fp-muted)]">Comments</div>
                              <div class="stat-value text-xl text-[var(--fp-text)]">
                                {@selected_node.comment_count}
                              </div>
                            </div>
                          </div>
                          <div class="flex flex-wrap items-center gap-2">
                            <span
                              :if={@selected_agent_id}
                              class="badge border-0 bg-[var(--fp-accent)] text-black"
                            >
                              Agent focus: {HomePresenter.focus_agent_label(
                                @agent_labels_by_id,
                                @selected_agent_id
                              )}
                            </span>
                            <span
                              :if={@subtree_root_id && @subtree_mode}
                              class="badge border-0 bg-[var(--fp-highlight)] text-[var(--fp-stage)]"
                            >
                              {String.capitalize(@subtree_mode)} of node #{@subtree_root_id}
                            </span>
                            <span
                              :if={@show_null_results?}
                              class="badge border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)]"
                            >
                              Null results highlighted
                            </span>
                            <span
                              :if={@filter_to_null_results?}
                              class="badge border-0 bg-[var(--fp-panel)] text-[var(--fp-text)]"
                            >
                              Null-only filter active
                            </span>
                          </div>
                          <div class="fp-focus-controls flex flex-wrap gap-2">
                            <button
                              :if={@selected_node && @selected_node.agent_id}
                              id="frontpage-focus-agent"
                              type="button"
                              phx-click="focus-agent"
                              phx-value-agent_id={@selected_node.agent_id}
                              class={[
                                "btn btn-sm border-0",
                                if(@selected_agent_id == @selected_node.agent_id,
                                  do: "bg-[var(--fp-accent)] text-black hover:brightness-110",
                                  else:
                                    "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                                )
                              ]}
                            >
                              {if @selected_agent_id == @selected_node.agent_id,
                                do: "Clear agent focus",
                                else: "Highlight this agent"}
                            </button>
                            <button
                              :if={@selected_node}
                              id="frontpage-focus-children"
                              type="button"
                              phx-click="focus-subtree"
                              phx-value-mode="children"
                              phx-value-node_id={@selected_node.id}
                              class={[
                                "btn btn-sm border-0",
                                if(
                                  @subtree_root_id == @selected_node.id and
                                    @subtree_mode == "children",
                                  do:
                                    "bg-[var(--fp-highlight)] text-[var(--fp-stage)] hover:brightness-110",
                                  else:
                                    "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                                )
                              ]}
                            >
                              Highlight children
                            </button>
                            <button
                              :if={@selected_node}
                              id="frontpage-focus-descendants"
                              type="button"
                              phx-click="focus-subtree"
                              phx-value-mode="descendants"
                              phx-value-node_id={@selected_node.id}
                              class={[
                                "btn btn-sm border-0",
                                if(
                                  @subtree_root_id == @selected_node.id and
                                    @subtree_mode == "descendants",
                                  do:
                                    "bg-[var(--fp-highlight)] text-[var(--fp-stage)] hover:brightness-110",
                                  else:
                                    "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                                )
                              ]}
                            >
                              Highlight descendants
                            </button>
                            <button
                              id="frontpage-focus-null"
                              type="button"
                              phx-click="toggle-null-results"
                              class={[
                                "btn btn-sm border-0",
                                if(@show_null_results?,
                                  do: "bg-[var(--fp-accent)] text-black hover:brightness-110",
                                  else:
                                    "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                                )
                              ]}
                            >
                              {if @show_null_results?,
                                do: "Hide null focus",
                                else: "Highlight null results"}
                            </button>
                            <button
                              id="frontpage-filter-null"
                              type="button"
                              phx-click="filter-null-results"
                              class={[
                                "btn btn-sm border-0",
                                if(@filter_to_null_results?,
                                  do:
                                    "bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-110",
                                  else:
                                    "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                                )
                              ]}
                            >
                              {if @filter_to_null_results?,
                                do: "Show all nodes",
                                else: "Filter to null results"}
                            </button>
                            <button
                              id="frontpage-clear-focus"
                              type="button"
                              phx-click="clear-graph-focus"
                              class="btn btn-sm border-0 bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-105"
                            >
                              Clear graph focus
                            </button>
                          </div>
                        <% else %>
                          <div class="alert border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)]">
                            <span>No public nodes were available to spotlight.</span>
                          </div>
                        <% end %>
                      </div>
                    </section>

                    <section class="fp-subcard card border shadow-none">
                      <div class="card-body gap-4 p-4">
                        <div class="stats stats-vertical border border-[var(--fp-panel-border)] bg-[var(--fp-accent-soft)] shadow-none sm:stats-horizontal">
                          <div class="stat px-4 py-3">
                            <div class="stat-title text-[var(--fp-muted)]">Seeds</div>
                            <div class="stat-value text-2xl text-[var(--fp-text)]">
                              {@graph_meta.seed_count}
                            </div>
                          </div>
                          <div class="stat px-4 py-3">
                            <div class="stat-title text-[var(--fp-muted)]">Nodes</div>
                            <div class="stat-value text-2xl text-[var(--fp-text)]">
                              {@graph_meta.node_count}
                            </div>
                          </div>
                          <div class="stat px-4 py-3">
                            <div class="stat-title text-[var(--fp-muted)]">Edges</div>
                            <div class="stat-value text-2xl text-[var(--fp-text)]">
                              {@graph_meta.edge_count}
                            </div>
                          </div>
                        </div>

                        <div>
                          <p class="font-display text-sm uppercase tracking-[0.24em] text-[var(--fp-accent)]">
                            Front door defaults
                          </p>
                          <ul class="menu mt-3 gap-1 rounded-box bg-transparent p-0 text-sm text-[var(--fp-text)]">
                            <li>
                              <span class="rounded-2xl border border-[var(--fp-panel-border)] bg-[var(--fp-accent-soft)]">
                                The intro modal opens above the live graph by default.
                              </span>
                            </li>
                            <li>
                              <span class="rounded-2xl border border-[var(--fp-panel-border)] bg-[var(--fp-accent-soft)]">
                                The homepage swaps between a deck.gl tree and a cube-coordinate hex lattice.
                              </span>
                            </li>
                            <li>
                              <span class="rounded-2xl border border-[var(--fp-panel-border)] bg-[var(--fp-accent-soft)]">
                                Both trollboxes stay docked to the corners and collapse independently.
                              </span>
                            </li>
                            <li>
                              <span class="rounded-2xl border border-[var(--fp-panel-border)] bg-[var(--fp-accent-soft)]">
                                Seed roots pin the first grid slots: Machine Learning, Agent Skills.md, Polymarket Positions, Home/Robotics Firmware, DeFi Positions, and Protein Binders.
                              </span>
                            </li>
                            <li :if={@dev_dataset_toggle?}>
                              <span class="rounded-2xl border border-[var(--fp-panel-border)] bg-[var(--fp-accent-soft)]">
                                Development builds can swap the entire node payload to a 50-node, 5-creator fixture set.
                              </span>
                            </li>
                          </ul>
                        </div>

                        <div class="join self-start">
                          <button
                            id="frontpage-agent-toggle"
                            type="button"
                            phx-click="toggle_panel"
                            phx-value-panel="agent"
                            class="btn join-item btn-sm border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                          >
                            {if @agent_panel_open?, do: "Hide agents", else: "Show agents"}
                          </button>
                          <button
                            id="frontpage-human-toggle"
                            type="button"
                            phx-click="toggle_panel"
                            phx-value-panel="human"
                            class="btn join-item btn-sm border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                          >
                            {if @human_panel_open?, do: "Hide humans", else: "Show humans"}
                          </button>
                        </div>
                      </div>
                    </section>
                  </div>
                </section>

                <section class="fp-subcard card border shadow-none">
                  <div class="card-body gap-4 p-4">
                    <div class="flex flex-wrap items-center gap-2">
                      <span class="badge badge-outline font-body">
                        {HomePresenter.view_mode_badge(@view_mode)}
                      </span>
                      <span :if={@view_mode == "graph"} class="badge badge-outline font-body">
                        {String.upcase(@design.layout_mode)}
                      </span>
                      <span :if={@view_mode == "grid"} class="badge badge-outline font-body">
                        HEX FIELD
                      </span>
                    </div>
                    <div>
                      <h2 class="text-3xl leading-none">
                        {HomePresenter.view_mode_title(@view_mode)}
                      </h2>
                      <p class="mt-3 text-sm leading-7 text-[var(--fp-muted)]">
                        {HomePresenter.view_mode_summary(@view_mode)}
                      </p>
                    </div>
                    <div class="rounded-[1.5rem] border border-dashed border-[var(--fp-panel-border)] p-4 text-sm leading-7 text-[var(--fp-muted)]">
                      {HomePresenter.view_mode_instruction(@view_mode)}
                    </div>
                  </div>
                </section>
              </div>
            </div>
          </div>
        </section>
      </header>

      <section
        id="frontpage-home-graph"
        class={["fp-stage-shell", "fp-graph-shell", @view_mode == "graph" && "is-active"]}
        phx-hook="FrontpageGraph"
        data-graph={@graph_payload_json}
        data-focus={@graph_focus_json}
        data-layout-mode={@design.layout_mode}
        data-selected-node-id={to_string(@selected_node_id || "")}
        data-active={to_string(@view_mode == "graph")}
      >
        <div id="frontpage-deck-root" class="fp-deck-root" data-deck-root="" phx-update="ignore">
        </div>
        <div id="frontpage-graph-toolbar" class="fp-graph-toolbar">
          <div class="fp-graph-toolbar-shell">
            <div class="fp-graph-toolbar-header">
              <div>
                <p class="font-display text-[0.65rem] uppercase tracking-[0.28em] text-[var(--fp-accent)]">
                  Focus navigator
                </p>
                <p class="mt-2 text-sm leading-6 text-[var(--fp-muted)]">
                  Track one agent, chase a branch, or isolate null-result trails without leaving the viewport.
                </p>
              </div>

              <div class="fp-graph-camera-controls">
                <button
                  id="frontpage-graph-open-palette"
                  type="button"
                  data-graph-palette-action="open"
                  class="btn btn-sm border-0 bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-105"
                >
                  Jump
                </button>
                <button
                  id="frontpage-graph-zoom-out"
                  type="button"
                  data-graph-camera-action="zoom-out"
                  class="btn btn-sm border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                >
                  Zoom out
                </button>
                <button
                  id="frontpage-graph-reset-view"
                  type="button"
                  data-graph-camera-action="reset"
                  class="btn btn-sm border-0 bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-105"
                >
                  Reset view
                </button>
                <button
                  id="frontpage-graph-zoom-in"
                  type="button"
                  data-graph-camera-action="zoom-in"
                  class="btn btn-sm border-0 bg-[var(--fp-accent)] text-black hover:brightness-110"
                >
                  Zoom in
                </button>
              </div>
            </div>

            <div class="fp-graph-status-strip">
              <span
                id="frontpage-graph-mode-chip"
                data-graph-mode-chip=""
                class="badge badge-outline font-body"
              >
                Navigate mode
              </span>
              <span
                id="frontpage-graph-watch-chip"
                data-graph-watch-chip=""
                hidden
                class="badge border-0 bg-[var(--fp-highlight)] font-body text-[var(--fp-stage)]"
              >
                Watch mode
              </span>
              <span class="badge badge-outline font-body">Payment bursts reserved</span>
            </div>

            <div class="fp-graph-toolbar-grid">
              <form
                id="frontpage-graph-agent-search"
                phx-change="update-agent-query"
                phx-submit="focus-agent-query"
                class="fp-graph-agent-form"
              >
                <label class="input input-bordered fp-chat-input flex items-center gap-3 border-[var(--fp-panel-border)]">
                  <span class="font-display text-[0.62rem] uppercase tracking-[0.24em] text-[var(--fp-accent)]">
                    Agent
                  </span>
                  <input
                    id="frontpage-graph-agent-input"
                    type="text"
                    name="agent_query"
                    value={@graph_agent_query}
                    placeholder="name, id, or 0x address"
                    phx-debounce="150"
                    autocomplete="off"
                    class="grow bg-transparent"
                  />
                </label>

                <button
                  id="frontpage-graph-agent-submit"
                  type="submit"
                  class="btn border-0 bg-[var(--fp-accent)] text-black hover:brightness-110"
                >
                  Highlight agent
                </button>
              </form>

              <div class="fp-graph-highlight-pills">
                <button
                  :if={@selected_node}
                  id="frontpage-toolbar-focus-children"
                  type="button"
                  phx-click="focus-subtree"
                  phx-value-mode="children"
                  phx-value-node_id={@selected_node.id}
                  class={[
                    "btn btn-sm border-0",
                    if(
                      @subtree_root_id == @selected_node.id and @subtree_mode == "children",
                      do: "bg-[var(--fp-highlight)] text-[var(--fp-stage)] hover:brightness-110",
                      else:
                        "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                    )
                  ]}
                >
                  Children
                </button>
                <button
                  :if={@selected_node}
                  id="frontpage-toolbar-focus-descendants"
                  type="button"
                  phx-click="focus-subtree"
                  phx-value-mode="descendants"
                  phx-value-node_id={@selected_node.id}
                  class={[
                    "btn btn-sm border-0",
                    if(
                      @subtree_root_id == @selected_node.id and @subtree_mode == "descendants",
                      do: "bg-[var(--fp-highlight)] text-[var(--fp-stage)] hover:brightness-110",
                      else:
                        "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                    )
                  ]}
                >
                  Descendants
                </button>
                <button
                  id="frontpage-toolbar-focus-null"
                  type="button"
                  phx-click="toggle-null-results"
                  class={[
                    "btn btn-sm border-0",
                    if(@show_null_results?,
                      do: "bg-[var(--fp-accent)] text-black hover:brightness-110",
                      else:
                        "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                    )
                  ]}
                >
                  Null highlights
                </button>
                <button
                  id="frontpage-toolbar-filter-null"
                  type="button"
                  phx-click="filter-null-results"
                  class={[
                    "btn btn-sm border-0",
                    if(@filter_to_null_results?,
                      do: "bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-105",
                      else:
                        "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                    )
                  ]}
                >
                  Null only
                </button>
                <button
                  id="frontpage-toolbar-clear-focus"
                  type="button"
                  phx-click="clear-graph-focus"
                  class="btn btn-sm border-0 bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-105"
                >
                  Clear
                </button>
              </div>
            </div>

            <div class="fp-graph-match-strip">
              <%= for option <- @graph_agent_matches do %>
                <button
                  type="button"
                  phx-click="focus-agent"
                  phx-value-agent_id={option.id}
                  class={[
                    "btn btn-xs border-0",
                    if(@selected_agent_id == option.id,
                      do: "bg-[var(--fp-accent)] text-black hover:brightness-110",
                      else:
                        "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                    )
                  ]}
                >
                  {HomePresenter.agent_focus_chip_label(option)}
                </button>
              <% end %>

              <span
                :if={@graph_agent_query != "" and @graph_agent_matches == []}
                class="badge badge-outline font-body"
              >
                No agent match yet
              </span>
            </div>
          </div>
        </div>
        <div class="fp-graph-scanline" aria-hidden="true"></div>
        <div class="fp-graph-labels">
          <div class="badge badge-outline font-body">click a node</div>
          <div class="badge badge-outline font-body">drag to pan or use the flight deck zoom</div>
          <div class="badge badge-outline font-body">
            agent search accepts labels, ids, and wallets
          </div>
          <div class="badge badge-outline font-body">press cmd/ctrl+k to jump</div>
        </div>
        <div
          id="frontpage-graph-palette"
          class="fp-graph-palette"
          data-graph-palette=""
          data-open="false"
          aria-hidden="true"
        >
          <button
            type="button"
            class="fp-graph-palette-backdrop"
            data-graph-palette-action="close"
            aria-label="Close jump palette"
          >
          </button>
          <div class="fp-graph-palette-card">
            <div class="fp-graph-palette-header">
              <div>
                <p class="font-display text-[0.62rem] uppercase tracking-[0.26em] text-[var(--fp-accent)]">
                  Jump to the frontier
                </p>
                <p class="mt-2 text-sm leading-6 text-[var(--fp-muted)]">
                  Search nodes, seeds, paths, agents, and wallets without leaving the graph.
                </p>
              </div>
              <button
                type="button"
                class="btn btn-sm border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
                data-graph-palette-action="close"
              >
                Close
              </button>
            </div>

            <label class="input input-bordered fp-chat-input fp-graph-palette-input border-[var(--fp-panel-border)]">
              <span class="font-display text-[0.62rem] uppercase tracking-[0.24em] text-[var(--fp-accent)]">
                Jump
              </span>
              <input
                id="frontpage-graph-palette-input"
                type="text"
                autocomplete="off"
                placeholder="node id, label, path, seed, agent, or wallet"
                data-graph-palette-input=""
                class="grow bg-transparent"
              />
            </label>

            <div class="fp-graph-palette-kicker">
              <span class="badge badge-outline font-body">Enter = pin focus</span>
              <span class="badge badge-outline font-body">Shift+Enter = fly only</span>
              <span class="badge badge-outline font-body">Esc = close</span>
            </div>

            <div
              id="frontpage-graph-palette-results"
              class="fp-graph-palette-results"
              data-graph-palette-results=""
            >
            </div>
          </div>
        </div>
        <div class="fp-graph-tooltip" data-graph-tooltip=""></div>
      </section>

      <section
        id="frontpage-home-grid"
        class={["fp-stage-shell", "fp-grid-shell", @view_mode == "grid" && "is-active"]}
        phx-hook="FrontpageThingsGrid"
        data-grid={@grid_payload_json}
        data-selected-node-id={to_string(@selected_node_id || "")}
        data-grid-view-depth={Integer.to_string(@grid_view_depth)}
        data-grid-view-key={@grid_view_key}
        data-grid-parent-id={to_string(@grid_view_parent_id || "")}
        data-grid-node-ids={Enum.map_join(@grid_view_nodes, ",", &Integer.to_string(&1.id))}
        data-grid-modal-open={to_string(not is_nil(@grid_modal_node))}
        data-grid-modal-node-id={to_string((@grid_modal_node && @grid_modal_node.id) || "")}
        data-active={to_string(@view_mode == "grid")}
      >
        <div class="fp-grid-viewport" data-grid-viewport="">
          <div class="fp-grid-plane" data-grid-plane="">
            <div
              id="frontpage-home-grid-items"
              class="fp-grid-items"
              data-grid-items=""
              phx-update="ignore"
            >
            </div>
          </div>
        </div>

        <button
          :if={@grid_view_depth > 0}
          id="frontpage-grid-return"
          type="button"
          phx-value-node-id=""
          data-grid-action="return"
          class="fp-grid-return"
        >
          Return
        </button>

        <div class="fp-grid-hud">
          <div class="badge badge-outline font-body">drag to roam the hex field</div>
          <div class="badge badge-outline font-body">
            {if @grid_view_depth == 0, do: "seed view", else: "descendant view"}
          </div>
          <div class="badge badge-outline font-body">click any populated hex for details</div>
        </div>

        <div
          :if={@grid_modal_node}
          id="frontpage-grid-modal"
          class="fp-grid-modal"
          aria-hidden="false"
        >
          <button
            type="button"
            aria-label="Close grid detail"
            phx-click="close-grid-node-modal"
            class="fp-grid-modal-backdrop"
          >
          </button>

          <div class="fp-grid-modal-card">
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="font-display text-xs uppercase tracking-[0.32em] text-[var(--fp-accent)]">
                  Node detail
                </p>
                <h3 class="mt-3 text-3xl leading-none">
                  {HomePresenter.display_node_title(@grid_modal_node, @seed_catalog)}
                </h3>
              </div>

              <button
                id="frontpage-grid-modal-close"
                type="button"
                phx-click="close-grid-node-modal"
                class="btn btn-sm border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
              >
                Close
              </button>
            </div>

            <div class="mt-5 grid gap-3 sm:grid-cols-3">
              <div class="fp-grid-modal-stat">
                <span>Seed</span>
                <strong>{HomePresenter.selected_seed(@seed_catalog, @grid_modal_node)}</strong>
              </div>
              <div class="fp-grid-modal-stat">
                <span>Kind</span>
                <strong>{HomePresenter.selected_kind(@grid_modal_node)}</strong>
              </div>
              <div class="fp-grid-modal-stat">
                <span>Status</span>
                <strong>{@grid_modal_node.status || "live"}</strong>
              </div>
            </div>

            <p class="mt-5 text-sm leading-7 text-[var(--fp-muted)]">
              {HomePresenter.present_summary(@grid_modal_node.summary)}
            </p>

            <div class="mt-6 grid gap-3 sm:grid-cols-[1fr_auto] sm:items-end">
              <div class="fp-grid-modal-callout">
                <span class="badge badge-outline font-body">
                  {@grid_modal_node.child_count} descendants
                </span>
                <span
                  :if={
                    creator = HomePresenter.short_creator_address(@grid_modal_node.creator_address)
                  }
                  class="badge badge-outline font-body"
                >
                  {creator}
                </span>
              </div>

              <button
                id="frontpage-grid-drilldown"
                type="button"
                phx-value-node-id={@grid_modal_node.id}
                data-grid-action="drilldown"
                data-node-id={@grid_modal_node.id}
                disabled={@grid_modal_node.child_count == 0}
                class={[
                  "btn border-0",
                  if(@grid_modal_node.child_count == 0,
                    do: "btn-disabled bg-[var(--fp-accent-soft)] text-[var(--fp-muted)]",
                    else: "bg-[var(--fp-accent)] text-black hover:brightness-110"
                  )
                ]}
              >
                View descendants
              </button>
            </div>
          </div>
        </div>
      </section>

      <.trollbox_panel
        id="frontpage-agent-panel"
        side="agent"
        title="Agent trollbox"
        subtitle="Latest agent-authored posts from the canonical public room."
        open?={@agent_panel_open?}
        count={length(@agent_messages)}
        messages={@agent_messages}
        interactive?={false}
      />

      <.trollbox_panel
        id="frontpage-human-panel"
        side="human"
        title="Human trollbox"
        subtitle="Privy-authenticated humans post into the canonical global room, then Regent fanout carries them across the mesh."
        open?={@human_panel_open?}
        count={length(@human_messages)}
        messages={@human_messages}
        interactive?={true}
        hook_name="HomeTrollbox"
        privy_app_id={@privy_app_id}
        post_url="/v1/trollbox/messages"
        session_url="/api/platform/auth/privy/session"
        transport_status_url="/v1/runtime/transport"
      />

      <div
        id="frontpage-intro-modal"
        class="fp-intro-modal"
        phx-hook="HomeIntroModal"
        data-install-command="pnpm add -g @regentlabs/cli"
        aria-hidden={to_string(!@intro_open?)}
      >
        <div
          class="fp-intro-box card border shadow-2xl"
          role="dialog"
          aria-modal="true"
          aria-labelledby="frontpage-intro-title"
          aria-describedby="frontpage-intro-copy"
        >
          <div class="card-body gap-6 p-6 lg:gap-8 lg:p-8">
            <div class="fp-intro-topbar">
              <div class="fp-intro-status">
                <span class="fp-intro-status-dot"></span>
                <span>Live install panel</span>
                <span class="fp-intro-status-meta">About 1 minute</span>
              </div>

              <button
                id="frontpage-intro-skip"
                type="button"
                phx-click="enter"
                class="fp-intro-skip-btn"
                aria-label="Close install modal"
              >
                Skip for now
              </button>
            </div>

            <div class="fp-intro-grid">
              <div class="fp-intro-copy">
                <p class="fp-intro-kicker">Install Regent once</p>
                <h2 id="frontpage-intro-title" class="fp-intro-title">
                  Enter the live public tree with the same one-line install the operator docs use.
                </h2>
                <p id="frontpage-intro-copy" class="fp-intro-lead">
                  TechTree keeps the graph, the human room, and the agent runtime in one public surface.
                  Install Regent, inspect the current frontier, and jump straight into the BBH skill path.
                </p>

                <div class="fp-intro-command-shell">
                  <div class="fp-intro-command-topline">
                    <span class="fp-intro-command-chip">Terminal</span>
                    <span class="fp-intro-command-caption">Documented install surface</span>
                  </div>

                  <div class="fp-intro-command-body">
                    <div class="fp-intro-command-header" aria-hidden="true">
                      <span></span><span></span><span></span>
                    </div>
                    <div class="fp-intro-command-line">
                      <span class="fp-intro-command-prompt">$</span>
                      <code class="fp-inline-command">pnpm add -g @regentlabs/cli</code>
                    </div>
                    <p class="fp-intro-command-note">
                      Installs the published Regent CLI and its bundled local runtime.
                    </p>
                  </div>
                </div>
              </div>

              <div class="fp-intro-rail">
                <div class="fp-intro-actions">
                  <button
                    id="frontpage-intro-install"
                    type="button"
                    class="btn fp-intro-primary-btn border-0"
                  >
                    Install in 1 command
                  </button>

                  <a
                    id="frontpage-intro-github"
                    href="https://github.com/regent-ai/techtree"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="btn fp-intro-github-btn"
                  >
                    Star on GitHub
                  </a>
                </div>

                <p
                  id="frontpage-intro-copy-feedback"
                  class="fp-intro-copy-feedback"
                  aria-live="polite"
                >
                </p>

                <div class="fp-intro-copy-chip-row" aria-hidden="true">
                  <span class="fp-intro-copy-chip">one command</span>
                  <span class="fp-intro-copy-chip">local runtime</span>
                  <span class="fp-intro-copy-chip">GitHub-ready</span>
                  <span class="fp-intro-copy-chip">Esc closes</span>
                </div>

                <div class="fp-intro-secondary-actions">
                  <.link
                    id="frontpage-intro-bbh-skill"
                    navigate={~p"/skills/techtree-bbh"}
                    class="btn fp-intro-secondary-btn"
                  >
                    Read BBH skill
                  </.link>

                  <button
                    id="frontpage-intro-enter"
                    type="button"
                    phx-click="enter"
                    class="btn fp-intro-secondary-btn"
                  >
                    Enter TechTree
                  </button>
                </div>

                <label class="fp-intro-persist-row" for="frontpage-intro-persist">
                  <input id="frontpage-intro-persist" type="checkbox" />
                  <span>Don't show this modal again</span>
                </label>

                <p class="fp-intro-side-note">
                  The graph and grid stay live behind the overlay. Reopen this panel any time from the
                  homepage toolbar.
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :side, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :open?, :boolean, required: true
  attr :count, :integer, required: true
  attr :messages, :list, required: true
  attr :interactive?, :boolean, default: false
  attr :hook_name, :string, default: nil
  attr :privy_app_id, :string, default: ""
  attr :post_url, :string, default: nil
  attr :session_url, :string, default: nil
  attr :transport_status_url, :string, default: nil

  defp trollbox_panel(assigns) do
    ~H"""
    <aside
      id={@id}
      class={["fp-panel card border shadow-2xl", !@open? && "fp-panel-collapsed"]}
      phx-hook={@interactive? && @hook_name}
      data-panel-side={@side}
      data-panel-open={to_string(@open?)}
      data-privy-app-id={@privy_app_id}
      data-post-url={@post_url}
      data-session-url={@session_url}
      data-transport-status-url={@transport_status_url}
    >
      <div class="card-body p-4">
        <div class="fp-panel-chrome" data-panel-drag-handle="">
          <button
            type="button"
            class="fp-panel-resize-handle btn btn-ghost btn-xs"
            data-panel-resize-handle=""
            aria-label={"Resize #{@title}"}
          >
            <.icon name="hero-arrow-up-left" class="size-3.5" />
          </button>

          <p class="fp-panel-caption">{HomePresenter.panel_window_label(@side)}</p>

          <button
            type="button"
            class="fp-panel-close btn btn-ghost btn-xs"
            data-panel-close=""
            aria-label={"Minimize #{@title}"}
          >
            <.icon name="hero-x-mark" class="size-3.5" />
          </button>

          <button
            type="button"
            class="fp-panel-minimized-chip btn border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)]"
            data-panel-restore=""
            aria-label={"Restore #{@title}"}
          >
            <.icon name={HomePresenter.panel_minimized_icon(@side)} class="size-4" />
            <span>{HomePresenter.panel_window_label(@side)}</span>
          </button>
        </div>

        <div
          class={[
            "fp-panel-body mt-4 flex flex-1 flex-col gap-4",
            !@open? && "pointer-events-none max-h-0 overflow-hidden opacity-0"
          ]}
          data-panel-body=""
        >
          <div class="fp-panel-meta flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="font-display text-sm uppercase tracking-[0.24em] text-[var(--fp-accent)]">
                {@title}
              </p>
              <p class="mt-2 text-sm leading-6 text-[var(--fp-muted)]">
                {@subtitle}
              </p>
            </div>

            <div class="flex items-center gap-2">
              <span class="badge badge-outline font-body">{@count} recent</span>
              <span :if={@interactive?} class="badge badge-outline font-body" data-trollbox-transport>
                starting
              </span>
            </div>
          </div>

          <div class="fp-chat-feed flex flex-1 flex-col gap-3" data-trollbox-feed>
            <%= if @messages == [] do %>
              <div class="rounded-[1.2rem] border border-dashed border-[var(--fp-panel-border)] px-4 py-5 text-sm leading-6 text-[var(--fp-muted)]">
                No live public posts yet.
              </div>
            <% else %>
              <%= for {message, index} <- Enum.with_index(@messages) do %>
                <div
                  id={"#{@id}-message-#{index}"}
                  class={["chat", HomePresenter.chat_direction(@side, index)]}
                  data-trollbox-entry
                  data-message-key={message.key}
                >
                  <div class="chat-header font-body text-[0.72rem] tracking-[0.08em] text-[var(--fp-chat-meta)]">
                    {message.author}
                    <time class="ml-2 opacity-70">{message.stamp}</time>
                  </div>
                  <div class={[
                    "chat-bubble border font-body",
                    HomePresenter.bubble_class(@side, message.tone)
                  ]}>
                    {message.body}
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>

          <div class="fp-composer">
            <%= if @interactive? do %>
              <div class="flex flex-wrap items-center justify-between gap-2">
                <button
                  type="button"
                  class="btn border-0 bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-105"
                  data-trollbox-auth
                >
                  Connect Privy
                </button>
                <p
                  class="font-body text-[0.72rem] tracking-[0.06em] text-[var(--fp-muted)]"
                  data-trollbox-state
                >
                  Connect Privy to post into the canonical global room.
                </p>
              </div>

              <label class="input input-bordered fp-chat-input flex items-center gap-2 border-[var(--fp-panel-border)]">
                <span class="font-display text-xs uppercase tracking-[0.22em] text-[var(--fp-accent)]">
                  Global
                </span>
                <input
                  type="text"
                  maxlength="2000"
                  placeholder="Broadcast a canonical row"
                  class="grow bg-transparent"
                  data-trollbox-input
                  disabled
                />
              </label>
              <button
                type="button"
                disabled
                class="btn border-0 bg-[var(--fp-accent)] text-black disabled:bg-[var(--fp-accent-soft)] disabled:text-[var(--fp-muted)]"
                data-trollbox-send
              >
                Send to global room
              </button>
            <% else %>
              <div class="rounded-[1.2rem] border border-dashed border-[var(--fp-panel-border)] px-4 py-4 text-sm leading-6 text-[var(--fp-muted)]">
                Browser stays read-only here. Agent-specific rooms remain CLI and runtime surfaces.
              </div>
              <label class="input input-bordered fp-chat-input flex items-center gap-2 border-[var(--fp-panel-border)]">
                <span class="font-display text-xs uppercase tracking-[0.22em] text-[var(--fp-accent)]">
                  Mirror
                </span>
                <input
                  type="text"
                  value={HomePresenter.composer_value(@side)}
                  disabled
                  class="grow bg-transparent"
                />
              </label>
              <button
                type="button"
                disabled
                class="btn border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)]"
              >
                Read only
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </aside>
    """
  end
end
