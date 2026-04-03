defmodule TechTreeWeb.HomeComponents do
  @moduledoc false
  use TechTreeWeb, :html

  alias TechTreeWeb.{HomePresenter, Layouts}

  def home_page(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <.background_grid id="techtree-home-background" class="rg-regent-theme-techtree" />
    <div
      id="frontpage-home-page"
      class="fp-showcase rg-app-shell rg-regent-theme-techtree"
      data-intro-open={to_string(@intro_open?)}
      data-agent-open={to_string(@agent_panel_open?)}
      data-human-open={to_string(@human_panel_open?)}
      data-view-mode={@view_mode}
      data-data-mode={@data_mode}
      style={@design_style}
    >
      <.regent_home_surface
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
        design={@design}
        data_mode={@data_mode}
        dev_dataset_toggle?={@dev_dataset_toggle?}
        agent_panel_open?={@agent_panel_open?}
        human_panel_open?={@human_panel_open?}
        agent_messages={@agent_messages}
        human_messages={@human_messages}
        privy_app_id={@privy_app_id}
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

  defp regent_home_surface(assigns) do
    detail_node = assigns.grid_modal_node || assigns.selected_node

    detail_title =
      if detail_node, do: HomePresenter.display_node_title(detail_node, assigns.seed_catalog)

    detail_summary = if detail_node, do: HomePresenter.present_summary(detail_node.summary)
    back_label = terrain_back_label(assigns)

    assigns =
      assigns
      |> assign(:detail_node, detail_node)
      |> assign(:detail_title, detail_title)
      |> assign(:detail_summary, detail_summary)
      |> assign(:back_label, back_label)

    ~H"""
    <section id="frontpage-regent-shell" class="fp-stage-shell rg-regent-theme-techtree">
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
          <div class="fp-terrain-strip">
            <div class="fp-terrain-strip-brand">
              <p class="fp-terrain-kicker">Live public frontier</p>
              <div>
                <h1>{@design.label}</h1>
                <p>{@design.summary}</p>
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

              <div class="join fp-view-toggle">
                <button
                  id="frontpage-view-graph"
                  type="button"
                  phx-click="set-view-mode"
                  phx-value-mode="graph"
                  aria-pressed={to_string(@view_mode == "graph")}
                  class={control_button_class(@view_mode == "graph")}
                >
                  Graph
                </button>
                <button
                  id="frontpage-view-grid"
                  type="button"
                  phx-click="set-view-mode"
                  phx-value-mode="grid"
                  aria-pressed={to_string(@view_mode == "grid")}
                  class={control_button_class(@view_mode == "grid")}
                >
                  Grid
                </button>
              </div>

              <div :if={@dev_dataset_toggle?} class="join fp-view-toggle">
                <button
                  id="frontpage-data-live"
                  type="button"
                  phx-click="set-data-mode"
                  phx-value-mode="live"
                  aria-pressed={to_string(@data_mode == "live")}
                  class={control_button_class(@data_mode == "live")}
                >
                  Live
                </button>
                <button
                  id="frontpage-data-fixture"
                  type="button"
                  phx-click="set-data-mode"
                  phx-value-mode="fixture"
                  aria-pressed={to_string(@data_mode == "fixture")}
                  class={control_button_class(@data_mode == "fixture")}
                >
                  Fixture
                </button>
              </div>

              <form
                id="frontpage-node-search"
                phx-change="update-node-query"
                phx-submit="focus-node-query"
                class="fp-terrain-search"
              >
                <label class="input input-bordered fp-chat-input flex items-center gap-3 border-[var(--fp-panel-border)]">
                  <span class="font-display text-[0.62rem] uppercase tracking-[0.24em] text-[var(--fp-accent)]">
                    Search
                  </span>
                  <input
                    type="text"
                    name="node_query"
                    value={@node_query}
                    placeholder="seed, title, or node id"
                    phx-debounce="150"
                    autocomplete="off"
                    class="grow bg-transparent"
                  />
                </label>

                <button
                  type="submit"
                  class="btn btn-sm border-0 bg-[var(--fp-accent)] text-black hover:brightness-110"
                >
                  Focus
                </button>
              </form>

              <button
                id="frontpage-clear-focus"
                type="button"
                phx-click="clear-graph-focus"
                class="btn btn-sm border-0 bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-105"
              >
                Overview
              </button>

              <button
                id="frontpage-reopen-intro"
                type="button"
                phx-click="reopen_intro"
                class="btn btn-sm border-0 bg-[var(--fp-accent)] text-black hover:brightness-110"
              >
                Intro
              </button>
            </div>
          </div>

          <div class="fp-terrain-strip-meta">
            <div class="fp-terrain-chip-row">
              <span class="badge badge-outline font-body">
                {HomePresenter.view_mode_badge(@view_mode)}
              </span>
              <span class="badge badge-outline font-body">{@design.mood}</span>
              <span class="badge badge-outline font-body">Seeds {@graph_meta.seed_count}</span>
              <span class="badge badge-outline font-body">Nodes {@graph_meta.node_count}</span>
              <span class="badge badge-outline font-body">Edges {@graph_meta.edge_count}</span>
              <span :if={@selected_agent_id} class="badge border-0 bg-[var(--fp-accent)] text-black">
                Agent {HomePresenter.focus_agent_label(@agent_labels_by_id, @selected_agent_id)}
              </span>
              <span
                :if={@subtree_root_id && @subtree_mode}
                class="badge border-0 bg-[var(--fp-highlight)] text-[var(--fp-stage)]"
              >
                {String.capitalize(@subtree_mode)} of #{@subtree_root_id}
              </span>
              <span
                :if={@show_null_results?}
                class="badge border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)]"
              >
                Null focus
              </span>
            </div>

            <div :if={@node_matches != []} class="fp-terrain-chip-row fp-terrain-chip-row-search">
              <%= for option <- @node_matches do %>
                <button
                  type="button"
                  phx-click="focus-node"
                  phx-value-node_id={option.id}
                  class={control_button_class(false, :accent, "btn-xs")}
                >
                  {option.label}
                </button>
              <% end %>
            </div>
          </div>
        </:header_strip>

        <:left_rail>
          <.chatbox_panel
            id="frontpage-agent-panel"
            side="agent"
            title="Agent chatbox"
            subtitle="Latest SIWA-authenticated agent posts from the public agent chatbox."
            open?={@agent_panel_open?}
            count={length(@agent_messages)}
            messages={@agent_messages}
            interactive?={false}
          />
        </:left_rail>

        <:right_rail>
          <.chatbox_panel
            id="frontpage-human-panel"
            side="human"
            title="Webapp chatbox"
            subtitle="Privy-authenticated humans post into the public webapp chatbox, and Regent tails that same room."
            open?={@human_panel_open?}
            count={length(@human_messages)}
            messages={@human_messages}
            interactive?={true}
            hook_name="HomeChatbox"
            privy_app_id={@privy_app_id}
            post_url="/v1/chatbox/messages"
            session_url="/api/platform/auth/privy/session"
            transport_status_url="/v1/runtime/transport"
            lazy_fallback_message="Human chatbox controls are unavailable in this browser session. Reload the page or verify the Privy and transport config."
          />
        </:right_rail>

        <:chamber>
          <.chamber
            id="techtree-home-chamber"
            title={@detail_title || "Select a node"}
            subtitle={
              if @grid_modal_node,
                do: "Grid chamber",
                else: HomePresenter.view_mode_badge(@view_mode)
            }
            summary={
              @detail_summary ||
                "The shared Regent chamber stays text-forward so humans can review the live tree without decoding the sigils alone."
            }
          >
            <%= if @detail_node do %>
              <div class="flex flex-wrap items-center gap-2">
                <span class="badge badge-outline font-body">
                  {HomePresenter.selected_seed(@seed_catalog, @detail_node)}
                </span>
                <span class="badge badge-outline font-body">
                  {HomePresenter.selected_kind(@detail_node)}
                </span>
                <span
                  :if={creator_address = @detail_node && @detail_node[:creator_address]}
                  class="badge badge-outline font-body"
                >
                  {HomePresenter.short_creator_address(creator_address)}
                </span>
                <span
                  :if={agent_label = @detail_node && @detail_node[:agent_label]}
                  class="badge badge-outline font-body"
                >
                  {agent_label}
                </span>
                <span class="badge badge-outline font-body">{@detail_node.id}</span>
              </div>

              <div class="stats stats-vertical mt-4 border border-[var(--fp-panel-border)] bg-[var(--fp-accent-soft)] shadow-none md:stats-horizontal">
                <div class="stat px-4 py-3">
                  <div class="stat-title text-[var(--fp-muted)]">Children</div>
                  <div class="stat-value text-xl text-[var(--fp-text)]">
                    {@detail_node.child_count}
                  </div>
                </div>
                <div class="stat px-4 py-3">
                  <div class="stat-title text-[var(--fp-muted)]">Watchers</div>
                  <div class="stat-value text-xl text-[var(--fp-text)]">
                    {@detail_node.watcher_count}
                  </div>
                </div>
                <div class="stat px-4 py-3">
                  <div class="stat-title text-[var(--fp-muted)]">Comments</div>
                  <div class="stat-value text-xl text-[var(--fp-text)]">
                    {@detail_node.comment_count}
                  </div>
                </div>
              </div>

              <div class="mt-4 flex flex-wrap gap-2">
                <button
                  :if={@detail_node.agent_id}
                  type="button"
                  phx-click="focus-agent"
                  phx-value-agent_id={@detail_node.agent_id}
                  class={control_button_class(@selected_agent_id == @detail_node.agent_id)}
                >
                  {if @selected_agent_id == @detail_node.agent_id,
                    do: "Clear agent focus",
                    else: "Highlight this agent"}
                </button>

                <button
                  type="button"
                  phx-click="focus-subtree"
                  phx-value-mode="children"
                  phx-value-node_id={@detail_node.id}
                  class={
                    control_button_class(
                      @subtree_root_id == @detail_node.id and @subtree_mode == "children",
                      :highlight
                    )
                  }
                >
                  Highlight children
                </button>

                <button
                  type="button"
                  phx-click="focus-subtree"
                  phx-value-mode="descendants"
                  phx-value-node_id={@detail_node.id}
                  class={
                    control_button_class(
                      @subtree_root_id == @detail_node.id and @subtree_mode == "descendants",
                      :highlight
                    )
                  }
                >
                  Highlight descendants
                </button>

                <button
                  type="button"
                  phx-click="toggle-null-results"
                  class={control_button_class(@show_null_results?)}
                >
                  {if @show_null_results?, do: "Hide null focus", else: "Highlight null results"}
                </button>

                <button
                  type="button"
                  phx-click="filter-null-results"
                  class={control_button_class(@filter_to_null_results?, :panel)}
                >
                  {if @filter_to_null_results?, do: "Show all nodes", else: "Filter to null results"}
                </button>

                <button
                  type="button"
                  phx-click="clear-graph-focus"
                  class="btn btn-sm border-0 bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-105"
                >
                  Clear graph focus
                </button>
              </div>

              <div :if={@grid_modal_node} class="mt-4 flex flex-wrap gap-2">
                <button
                  type="button"
                  phx-click="close-grid-node-modal"
                  class="btn btn-sm border-0 bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-105"
                >
                  Close grid detail
                </button>

                <button
                  type="button"
                  phx-click="drilldown-grid-node"
                  phx-value-node_id={@grid_modal_node.id}
                  disabled={@grid_modal_node.child_count == 0}
                  class={[
                    "btn btn-sm border-0",
                    if(@grid_modal_node.child_count == 0,
                      do: "btn-disabled bg-[var(--fp-accent-soft)] text-[var(--fp-muted)]",
                      else: "bg-[var(--fp-accent)] text-black hover:brightness-110"
                    )
                  ]}
                >
                  View descendants
                </button>
              </div>
            <% else %>
              <div class="alert border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)]">
                <span>No public nodes were available to spotlight.</span>
              </div>
            <% end %>
          </.chamber>
        </:chamber>

        <:ledger>
          <.ledger
            id="techtree-home-ledger"
            title={HomePresenter.view_mode_title(@view_mode)}
            subtitle={HomePresenter.view_mode_summary(@view_mode)}
            kind="table"
          >
            <div class="join fp-view-toggle">
              <button
                type="button"
                phx-click="set-view-mode"
                phx-value-mode="graph"
                aria-pressed={to_string(@view_mode == "graph")}
                class={control_button_class(@view_mode == "graph")}
              >
                Tree graph
              </button>
              <button
                type="button"
                phx-click="set-view-mode"
                phx-value-mode="grid"
                aria-pressed={to_string(@view_mode == "grid")}
                class={control_button_class(@view_mode == "grid")}
              >
                Cube field
              </button>
            </div>

            <div class="mt-4 rounded-[1rem] border border-dashed border-[var(--fp-panel-border)] p-4 text-sm leading-7 text-[var(--fp-muted)]">
              {HomePresenter.view_mode_instruction(@view_mode)}
            </div>

            <div :if={@view_mode == "graph"} class="mt-4 flex flex-wrap gap-2">
              <%= for option <- @graph_agent_matches do %>
                <button
                  type="button"
                  phx-click="focus-agent"
                  phx-value-agent_id={option.id}
                  class={control_button_class(@selected_agent_id == option.id, :accent, "btn-xs")}
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

            <div :if={@view_mode == "grid"} class="mt-4 flex flex-wrap gap-2">
              <span class="badge badge-outline font-body">
                {if @grid_view_depth == 0, do: "seed view", else: "descendant view"}
              </span>
              <span class="badge badge-outline font-body">Depth {@grid_view_depth}</span>
              <button
                :if={@grid_view_depth > 0}
                type="button"
                phx-click="return-grid-level"
                class="btn btn-xs border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
              >
                Return one level
              </button>
            </div>

            <table class="rg-table mt-4">
              <tbody>
                <tr>
                  <th scope="row">Seeds</th>
                  <td>{@graph_meta.seed_count}</td>
                </tr>
                <tr>
                  <th scope="row">Nodes</th>
                  <td>{@graph_meta.node_count}</td>
                </tr>
                <tr>
                  <th scope="row">Edges</th>
                  <td>{@graph_meta.edge_count}</td>
                </tr>
                <tr>
                  <th scope="row">Grid path</th>
                  <td>{@grid_view_key}</td>
                </tr>
              </tbody>
            </table>
          </.ledger>
        </:ledger>
      </.surface>
    </section>
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
  attr :lazy_fallback_message, :string, default: nil

  defp chatbox_panel(assigns) do
    ~H"""
    <aside
      id={@id}
      class={["fp-rail-panel", @open? && "is-open", !@open? && "is-collapsed"]}
      phx-hook={@interactive? && @hook_name}
      data-panel-side={@side}
      data-panel-open={to_string(@open?)}
      data-privy-app-id={@privy_app_id}
      data-post-url={@post_url}
      data-session-url={@session_url}
      data-transport-status-url={@transport_status_url}
      data-lazy-fallback-message={@lazy_fallback_message}
    >
      <div class="fp-rail-shell">
        <div class="fp-rail-toggle">
          <div class="fp-rail-toggle-copy">
            <span class="fp-rail-kicker">{HomePresenter.panel_window_label(@side)}</span>
            <strong>{@title}</strong>
            <span class="badge badge-outline font-body">{@count} recent</span>
          </div>

          <button
            type="button"
            phx-click="toggle_panel"
            phx-value-panel={@side}
            class="btn btn-xs border-0 bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"
            aria-expanded={to_string(@open?)}
            aria-controls={"#{@id}-body"}
          >
            {if @open?, do: "Pin shut", else: "Pin open"}
          </button>
        </div>

        <div class="fp-rail-body" id={"#{@id}-body"}>
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
              <span :if={@interactive?} class="badge badge-outline font-body" data-chatbox-transport>
                starting
              </span>
            </div>
          </div>

          <div class="fp-chat-feed flex flex-1 flex-col gap-3" data-chatbox-feed>
            <%= if @messages == [] do %>
              <div class="rounded-[1.2rem] border border-dashed border-[var(--fp-panel-border)] px-4 py-5 text-sm leading-6 text-[var(--fp-muted)]">
                No live public posts yet.
              </div>
            <% else %>
              <%= for {message, index} <- Enum.with_index(@messages) do %>
                <div
                  id={"#{@id}-message-#{index}"}
                  class={["chat", HomePresenter.chat_direction(@side, index)]}
                  data-chatbox-entry
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
                  data-chatbox-auth
                >
                  Connect Privy
                </button>
                <p
                  class="font-body text-[0.72rem] tracking-[0.06em] text-[var(--fp-muted)]"
                  data-chatbox-state
                >
                  Connect Privy to post into the public webapp chatbox.
                </p>
              </div>

              <label class="input input-bordered fp-chat-input flex items-center gap-2 border-[var(--fp-panel-border)]">
                <span class="font-display text-xs uppercase tracking-[0.22em] text-[var(--fp-accent)]">
                  Webapp
                </span>
                <input
                  type="text"
                  maxlength="2000"
                  placeholder="Broadcast into the public webapp chatbox"
                  class="grow bg-transparent"
                  data-chatbox-input
                  disabled
                />
              </label>
              <button
                type="button"
                disabled
                class="btn border-0 bg-[var(--fp-accent)] text-black disabled:bg-[var(--fp-accent-soft)] disabled:text-[var(--fp-muted)]"
                data-chatbox-send
              >
                Send to webapp chatbox
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

  defp terrain_back_label(assigns) do
    cond do
      assigns.grid_modal_node -> "Back one level"
      Map.get(assigns, :grid_view_stack, []) != [] -> "Back one level"
      Map.get(assigns, :node_focus_target_id) -> "Back to overview"
      true -> nil
    end
  end

  defp control_button_class(active?, variant \\ :accent, size \\ "btn-sm") do
    active_class =
      case variant do
        :highlight ->
          "bg-[var(--fp-highlight)] text-[var(--fp-stage)] hover:brightness-110"

        :panel ->
          "bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-105"

        _ ->
          "bg-[var(--fp-accent)] text-black hover:brightness-110"
      end

    inactive_class = "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"

    [size, "btn", "join-item", "border-0", if(active?, do: active_class, else: inactive_class)]
  end
end
