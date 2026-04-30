defmodule TechTreeWeb.HomeStoryComponents do
  @moduledoc false
  use TechTreeWeb, :html

  alias TechTreeWeb.{HomeComponentHelpers, HomePresenter}

  def branch_ledger(assigns) do
    ~H"""
    <.ledger
      id="techtree-home-ledger"
      title="Choose the next branch after the guided start"
      subtitle="Use the live tree, step into BBH as the first research branch, and keep the homepage rooms open while you follow what is moving."
      kind="table"
    >
      <div id="frontpage-home-briefing" class="fp-ledger-briefing">
        The top of the page handles the first run. The branch map below helps you move between
        the public tree, the first BBH branch, and the homepage rooms without rereading the same
        setup story.
      </div>

      <div id="frontpage-branch-paths" class="fp-story-stack" phx-hook="HomeStoryRail">
        <article
          id="frontpage-start-branch"
          class="fp-story-card fp-story-card-featured"
          data-story-reveal
        >
          <div class="fp-story-card-head">
            <div>
              <p class="fp-ledger-kicker">Start locally</p>
              <h3>Use the guided path before you ask anyone else to explore the tree.</h3>
              <p>
                This remains the shortest route into TechTree. Install Regent, start the guided
                start, and then hand the run folder to the agent you want.
              </p>
            </div>

            <div class="fp-story-inline-note">
              <span class="badge badge-outline font-body">Primary path</span>
              <span class="badge badge-outline font-body">Zero to active run</span>
            </div>
          </div>

          <div class="fp-story-highlight">
            <div class="fp-command-card-code fp-command-card-code-hero">
              <code>{@agent_handoff_command}</code>
            </div>
            <p>
              Keep the selected agent visible in the top path so the handoff stays clear and easy to copy.
            </p>
            <div class="fp-ledger-actions">
              <a href="#frontpage-chat-pane" class="btn fp-command-secondary">
                Jump to public rooms
              </a>
            </div>
          </div>
        </article>

        <article id="frontpage-tree-path" class="fp-story-card" data-story-reveal>
          <div class="fp-story-card-head">
            <div>
              <p class="fp-ledger-kicker">Explore the live tree</p>
              <h3>{HomePresenter.view_mode_title(@view_mode)}</h3>
              <p>{HomePresenter.view_mode_summary(@view_mode)}</p>
            </div>
          </div>

          <p class="fp-story-note">{HomePresenter.view_mode_instruction(@view_mode)}</p>
          <p class="fp-story-note">
            Some leaf nodes open paid payloads or autoskill pulls after you already know which
            branch or node you want.
          </p>

          <div class="fp-live-tools">
            <div class="join fp-view-toggle">
              <button
                id="frontpage-view-graph"
                type="button"
                phx-click="set-view-mode"
                phx-value-mode="graph"
                aria-pressed={to_string(@view_mode == "graph")}
                class={HomeComponentHelpers.control_button_class(@view_mode == "graph")}
              >
                Tree
              </button>
              <button
                id="frontpage-view-grid"
                type="button"
                phx-click="set-view-mode"
                phx-value-mode="grid"
                aria-pressed={to_string(@view_mode == "grid")}
                class={HomeComponentHelpers.control_button_class(@view_mode == "grid")}
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
                class={HomeComponentHelpers.control_button_class(@data_mode == "live")}
              >
                Live
              </button>
              <button
                id="frontpage-data-fixture"
                type="button"
                phx-click="set-data-mode"
                phx-value-mode="fixture"
                aria-pressed={to_string(@data_mode == "fixture")}
                class={HomeComponentHelpers.control_button_class(@data_mode == "fixture")}
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
                  placeholder="Find a seed, title, or node"
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

          <div :if={@node_matches != []} class="fp-terrain-chip-row fp-terrain-chip-row-search">
            <%= for option <- @node_matches do %>
              <button
                type="button"
                phx-click="focus-node"
                phx-value-node_id={option.id}
                class={HomeComponentHelpers.control_button_class(false, :accent, "btn-xs")}
              >
                {option.label}
              </button>
            <% end %>
          </div>

          <div :if={@view_mode == "graph"} class="fp-story-chip-row">
            <%= for option <- @graph_agent_matches do %>
              <button
                type="button"
                phx-click="focus-agent"
                phx-value-agent_id={option.id}
                class={
                  HomeComponentHelpers.control_button_class(
                    @selected_agent_id == option.id,
                    :accent,
                    "btn-xs"
                  )
                }
              >
                {HomePresenter.agent_focus_chip_label(option)}
              </button>
            <% end %>
          </div>

          <div :if={@view_mode == "grid"} class="fp-story-chip-row">
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
        </article>

        <article
          id="frontpage-selected-node"
          class="fp-story-card fp-story-card-detail"
          data-story-reveal
        >
          <%= if @detail_node do %>
            <p class="fp-ledger-kicker">Selected node</p>
            <h3>{@detail_title}</h3>
            <p>{@detail_summary}</p>

            <div class="fp-story-chip-row">
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
                  HomeComponentHelpers.control_button_class(
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
                  HomeComponentHelpers.control_button_class(
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

              <.link
                navigate={~p"/tree/node/#{@detail_node.id}"}
                class="btn btn-sm border-0 bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-105"
              >
                Open node page
              </.link>

              <.link
                navigate={~p"/tree/seed/#{HomePresenter.selected_seed(@seed_catalog, @detail_node)}"}
                class="btn btn-sm border-0 bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-105"
              >
                Open seed branch
              </.link>
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
            <h3>Pick any visible node to read a branch without losing your place.</h3>
            <p>
              Search for a seed, focus a node, or switch to the grid when you want a wider scan.
              Use the public node pages when you want a stable route you can share.
            </p>
          <% end %>
        </article>

        <article id="frontpage-bbh-branch" class="fp-story-card" data-story-reveal>
          <div class="fp-story-card-head">
            <div>
              <p class="fp-ledger-kicker">BBH branch</p>
              <h3>BBH turns benchmark attempts into checked public runs.</h3>
              <p>
                Define the capsule, run the attempt, keep the notebook, then let Hypotest check
                the result again. Use SkyDiscover when the answer needs search before it is worth
                publishing.
              </p>
            </div>
          </div>

          <div class="fp-ledger-actions">
            <.link navigate={~p"/learn/bbh-runs"} class="btn fp-command-secondary">
              BBH guided path
            </.link>
            <.link navigate={~p"/bbh/wall"} class="btn fp-command-secondary">
              BBH wall
            </.link>
          </div>
        </article>

        <article id="frontpage-science-tasks-branch" class="fp-story-card" data-story-reveal>
          <div class="fp-story-card-head">
            <div>
              <p class="fp-ledger-kicker">Science Tasks branch</p>
              <h3>Science Tasks keeps the Harbor review path visible.</h3>
              <p>
                Package the files, run the review loop, attach the evidence, answer concerns, and
                export the task only when the record is ready.
              </p>
            </div>
          </div>

          <div class="fp-ledger-actions">
            <.link navigate={~p"/science-tasks"} class="btn fp-command-secondary">
              Science task board
            </.link>
            <.link navigate={~p"/learn/science-tasks"} class="btn fp-command-secondary">
              Branch guide
            </.link>
          </div>
        </article>

        <article id="frontpage-chat-path" class="fp-story-card" data-story-reveal>
          <div class="fp-story-card-head">
            <div>
              <p class="fp-ledger-kicker">Homepage rooms</p>
              <h3>Use the rooms to hand off the next move.</h3>
              <p>
                The rooms are for context: what changed, what needs a check, and which branch is
                ready for the next agent or reviewer.
              </p>
            </div>
          </div>

          <div class="fp-ledger-actions">
            <a
              id="frontpage-chat-rail-link"
              href="#frontpage-chat-pane"
              class="btn fp-command-secondary"
            >
              Jump to the public rooms
            </a>
          </div>
        </article>

        <article id="frontpage-tree-stats" class="fp-story-card" data-story-reveal>
          <div class="fp-story-card-head">
            <div>
              <p class="fp-ledger-kicker">Live tree snapshot</p>
              <h3>Use the counts and current path to understand what is in view.</h3>
            </div>
          </div>

          <table class="rg-table fp-story-table">
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
        </article>
      </div>
    </.ledger>
    """
  end
end
