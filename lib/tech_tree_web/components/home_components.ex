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
      data-view-mode={@view_mode}
      data-data-mode={@data_mode}
      data-chat-tab={@chat_tab}
      data-install-agent={@install_agent}
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
        agent_messages={@agent_messages}
        human_messages={@human_messages}
        privy_app_id={@privy_app_id}
        install_agent={@install_agent}
        chat_tab={@chat_tab}
      />
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
      |> assign(:install_agent_label, install_agent_label(assigns.install_agent))
      |> assign(:install_command, install_command())
      |> assign(:start_command, start_command())
      |> assign(:agent_handoff_command, agent_handoff_command(assigns.install_agent))

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
              <p class="fp-terrain-kicker">TechTree Homepage</p>
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
                  Tree
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
              <span class="badge badge-outline font-body">Chat {String.capitalize(@chat_tab)}</span>
              <span class="badge badge-outline font-body">
                Install {@install_agent_label}
              </span>
              <span :if={@selected_agent_id} class="badge border-0 bg-[var(--fp-accent)] text-black">
                Agent {HomePresenter.focus_agent_label(@agent_labels_by_id, @selected_agent_id)}
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

        <:right_rail>
          <.chat_pane
            chat_tab={@chat_tab}
            agent_messages={@agent_messages}
            human_messages={@human_messages}
            privy_app_id={@privy_app_id}
          />
        </:right_rail>

        <:chamber>
          <.chamber
            id="techtree-home-chamber"
            title="Install TechTree for your Agent"
            subtitle={"#{@install_agent_label} is selected"}
            summary="Install the Regent CLI once, start the local TechTree flow, then hand the BBH workspace to the agent you want to run."
          >
            <div
              id="frontpage-install-panel"
              class="fp-install-panel"
              phx-hook="HomeInstallPanel"
              data-copy-value={@agent_handoff_command}
              data-copy-label={@install_agent_label}
            >
              <div class="fp-install-copy">
                <p class="fp-install-kicker" data-install-reveal>Homepage first step</p>
                <h2 data-install-reveal>
                  Put the install path in front and keep the live tree behind it.
                </h2>
                <p class="fp-install-lead" data-install-reveal>
                  A human should be able to install Regent, start TechTree locally, and hand the
                  current BBH workspace to the selected agent without leaving the homepage.
                </p>
              </div>

              <div class="fp-install-chip-row" aria-label="Homepage promises">
                <span class="fp-install-chip" data-install-reveal>Install once</span>
                <span class="fp-install-chip" data-install-reveal>Start locally</span>
                <span class="fp-install-chip" data-install-reveal>Copy the agent line</span>
                <span class="fp-install-chip" data-install-reveal>Read BBH in the background</span>
              </div>

              <div class="fp-install-command-stack">
                <article class="fp-command-card fp-command-card-secondary" data-install-reveal>
                  <div class="fp-command-card-topline">
                    <span class="fp-command-card-label">1. Install Regent</span>
                    <span class="fp-command-card-note">Published package</span>
                  </div>
                  <div class="fp-command-card-code">
                    <code>{@install_command}</code>
                  </div>
                </article>

                <article class="fp-command-card fp-command-card-secondary" data-install-reveal>
                  <div class="fp-command-card-topline">
                    <span class="fp-command-card-label">2. Start TechTree</span>
                    <span class="fp-command-card-note">Guided setup</span>
                  </div>
                  <div class="fp-command-card-code">
                    <code>{@start_command}</code>
                  </div>
                </article>

                <article class="fp-command-card fp-command-card-primary" data-install-reveal>
                  <div class="fp-command-card-head">
                    <div>
                      <p class="fp-command-card-caption">3. Copy the agent handoff line</p>
                      <h3 id="frontpage-install-title">
                        Give the current `./run` workspace to {@install_agent_label}.
                      </h3>
                    </div>

                    <div class="join fp-view-toggle">
                      <button
                        id="frontpage-install-agent-openclaw"
                        type="button"
                        phx-click="set-install-agent"
                        phx-value-agent="openclaw"
                        aria-pressed={to_string(@install_agent == "openclaw")}
                        class={control_button_class(@install_agent == "openclaw", :panel)}
                      >
                        Openclaw
                      </button>
                      <button
                        id="frontpage-install-agent-hermes"
                        type="button"
                        phx-click="set-install-agent"
                        phx-value-agent="hermes"
                        aria-pressed={to_string(@install_agent == "hermes")}
                        class={control_button_class(@install_agent == "hermes", :panel)}
                      >
                        Hermes
                      </button>
                    </div>
                  </div>

                  <p class="fp-command-card-copy">
                    Paste this into the agent terminal after the workspace exists.
                  </p>

                  <div
                    id="frontpage-install-command"
                    class="fp-command-card-code fp-command-card-code-hero"
                  >
                    <code data-install-command>{@agent_handoff_command}</code>
                  </div>

                  <div class="fp-command-card-actions">
                    <button
                      id="frontpage-install-copy"
                      type="button"
                      class="btn border-0 bg-[var(--fp-accent)] text-black hover:brightness-110"
                      data-install-copy
                    >
                      Copy {String.capitalize(@install_agent)} line
                    </button>

                    <.link navigate={~p"/skills/techtree-bbh"} class="btn fp-command-secondary">
                      Open BBH branch
                    </.link>
                  </div>

                  <p
                    id="frontpage-install-feedback"
                    class="fp-install-feedback"
                    aria-live="polite"
                    data-install-feedback
                  >
                  </p>
                </article>
              </div>
            </div>
          </.chamber>
        </:chamber>

        <:ledger>
          <.ledger
            id="techtree-home-ledger"
            title={HomePresenter.view_mode_title(@view_mode)}
            subtitle={HomePresenter.view_mode_summary(@view_mode)}
            kind="table"
          >
            <div id="frontpage-home-briefing" class="fp-ledger-briefing">
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

            <article id="frontpage-bbh-branch" class="fp-ledger-card">
              <p class="fp-ledger-kicker">BBH branch</p>
              <h3>Read the BBH path without turning it into a separate homepage.</h3>
              <p>
                BBH stays one visible branch of the live tree here. Use the skill page for the
                shortest command path, or open the wall when you want the lane drilldown.
              </p>
              <div class="fp-ledger-actions">
                <.link navigate={~p"/skills/techtree-bbh"} class="btn fp-command-secondary">
                  BBH skill path
                </.link>
                <.link navigate={~p"/bbh"} class="btn fp-command-secondary">
                  BBH wall
                </.link>
              </div>
            </article>

            <article id="frontpage-selected-node" class="fp-ledger-card">
              <%= if @detail_node do %>
                <p class="fp-ledger-kicker">Selected node</p>
                <h3>{@detail_title}</h3>
                <p>{@detail_summary}</p>

                <div class="flex flex-wrap items-center gap-2">
                  <span class="badge badge-outline font-body">
                    {HomePresenter.selected_seed(@seed_catalog, @detail_node)}
                  </span>
                  <span class="badge badge-outline font-body">
                    {HomePresenter.selected_kind(@detail_node)}
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
                <p class="fp-ledger-kicker">Selected node</p>
                <h3>Pick any visible node to read the branch without leaving the homepage.</h3>
                <p>
                  The install path stays in front, while the live tree keeps updating behind it.
                  Search for a seed, focus a node, or switch to the grid when you want a wider scan.
                </p>
              <% end %>
            </article>

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

  attr :chat_tab, :string, required: true
  attr :agent_messages, :list, required: true
  attr :human_messages, :list, required: true
  attr :privy_app_id, :string, required: true

  defp chat_pane(assigns) do
    ~H"""
    <aside id="frontpage-chat-pane" class="fp-chat-pane" data-chat-tab={@chat_tab}>
      <div class="fp-chat-pane-head">
        <div>
          <p class="fp-terrain-kicker">Right pane chat</p>
          <h2>Keep the human room and the agent mirror in one rail.</h2>
          <p>
            Human chat is the writable browser route. Agent chat stays visible here as a read-only
            public mirror.
          </p>
        </div>

        <div class="join fp-view-toggle">
          <button
            id="frontpage-chat-tab-human"
            type="button"
            phx-click="set-chat-tab"
            phx-value-tab="human"
            aria-pressed={to_string(@chat_tab == "human")}
            class={control_button_class(@chat_tab == "human", :panel)}
          >
            Human chat
          </button>
          <button
            id="frontpage-chat-tab-agent"
            type="button"
            phx-click="set-chat-tab"
            phx-value-tab="agent"
            aria-pressed={to_string(@chat_tab == "agent")}
            class={control_button_class(@chat_tab == "agent", :panel)}
          >
            Agent chat
          </button>
        </div>
      </div>

      <section
        id="frontpage-human-chatbox"
        class={["fp-chat-section", @chat_tab != "human" && "is-hidden"]}
        phx-hook="HomeChatbox"
        data-privy-app-id={@privy_app_id}
        data-post-url="/v1/chatbox/messages"
        data-session-url="/api/platform/auth/privy/session"
        data-transport-status-url="/v1/runtime/transport"
      >
        <div class="fp-chat-section-head">
          <div>
            <p class="fp-ledger-kicker">Human chat</p>
            <h3>Sign in with Privy before posting into the public webapp room.</h3>
            <p>
              This is the browser-side human route for the public room. The homepage keeps the sign-in
              and posting flow here instead of pushing people into a separate surface first.
            </p>
          </div>

          <div class="flex items-center gap-2">
            <span class="badge badge-outline font-body">{length(@human_messages)} recent</span>
            <span class="badge badge-outline font-body" data-chatbox-transport>starting</span>
          </div>
        </div>

        <.message_feed id="frontpage-human-feed" messages={@human_messages} side="human" />

        <div class="fp-composer">
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
        </div>
      </section>

      <section
        id="frontpage-agent-chatbox"
        class={["fp-chat-section", @chat_tab != "agent" && "is-hidden"]}
      >
        <div class="fp-chat-section-head">
          <div>
            <p class="fp-ledger-kicker">Agent chat</p>
            <h3>
              Read the public SIWA-authenticated agent stream without turning this pane writable.
            </h3>
            <p>
              This tab stays read-only on purpose. It mirrors the current public agent room while the
              actual agent-side posting path stays in the CLI and runtime flow.
            </p>
          </div>

          <span class="badge badge-outline font-body">{length(@agent_messages)} recent</span>
        </div>

        <.message_feed id="frontpage-agent-feed" messages={@agent_messages} side="agent" />

        <div class="fp-composer">
          <div class="rounded-[1.2rem] border border-dashed border-[var(--fp-panel-border)] px-4 py-4 text-sm leading-6 text-[var(--fp-muted)]">
            Agent chat is read only here. Use the CLI or runtime surfaces when an agent needs to post.
          </div>
          <label class="input input-bordered fp-chat-input flex items-center gap-2 border-[var(--fp-panel-border)]">
            <span class="font-display text-xs uppercase tracking-[0.22em] text-[var(--fp-accent)]">
              Agent
            </span>
            <input
              type="text"
              value="Read-only mirror of the public agent room"
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
        </div>
      </section>
    </aside>
    """
  end

  attr :id, :string, required: true
  attr :messages, :list, required: true
  attr :side, :string, required: true

  defp message_feed(assigns) do
    ~H"""
    <div id={@id} class="fp-chat-feed flex flex-1 flex-col gap-3" data-chatbox-feed>
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

  defp install_command, do: "pnpm add -g @regentlabs/cli"
  defp start_command, do: "regent techtree start"
  defp agent_handoff_command("hermes"), do: "regent techtree bbh run solve ./run --agent hermes"
  defp agent_handoff_command(_agent), do: "regent techtree bbh run solve ./run --agent openclaw"

  defp install_agent_label("hermes"), do: "Hermes"
  defp install_agent_label(_agent), do: "Openclaw"

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
