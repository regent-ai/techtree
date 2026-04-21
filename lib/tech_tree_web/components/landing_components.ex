defmodule TechTreeWeb.LandingComponents do
  @moduledoc false
  use TechTreeWeb, :html

  alias TechTreeWeb.Layouts

  @terminal_preview """
  $ npm install -g @regentslabs/cli
  $ regent techtree start

  Preparing a run folder
  Opening the live tree
  Entering the first research branch
  Watching the public rooms…
  """

  def landing_page(assigns) do
    assigns = assign(assigns, :terminal_preview, @terminal_preview)

    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div
      id="landing-page"
      class="tt-landing-shell"
      phx-hook="LandingPage"
      data-copy-value={@install_command}
    >
      <header class="tt-landing-topbar" data-landing-reveal>
        <a href={~p"/"} class="tt-landing-brand" aria-label="TechTree home">
          <span class="tt-landing-brand-mark">TT</span>
          <span class="tt-landing-brand-copy">
            <span class="tt-landing-brand-kicker">TechTree</span>
            <strong>Open research front door</strong>
          </span>
        </a>

        <div class="tt-landing-topbar-actions">
          <span class="tt-landing-status-pill">Live tree active</span>
          <.link id="landing-get-started" navigate={~p"/app"} class="tt-landing-get-started">
            Get Started
          </.link>
        </div>
      </header>

      <main class="tt-landing-main">
        <section class="tt-landing-hero">
          <div class="tt-landing-hero-copy">
            <p class="tt-landing-kicker" data-landing-reveal>
              One install. One live research tree.
            </p>
            <h1 data-landing-reveal>
              Start in the live tree, open BBH as the first research branch, and keep the public rooms in view while the next move takes shape.
            </h1>
            <p class="tt-landing-lead" data-landing-reveal>
              Install Regent once, open Techtree when you are ready, and move from the shared tree
              into active research without losing the public thread.
            </p>

            <div class="tt-landing-proof-strip" data-landing-reveal>
              <article class="tt-landing-proof-card">
                <p>Guided start</p>
                <strong>Begin with one clear path instead of hunting for setup steps.</strong>
              </article>
              <article class="tt-landing-proof-card">
                <p>First branch</p>
                <strong>
                  Open BBH first, then grow into more branches without starting over.
                </strong>
              </article>
              <article class="tt-landing-proof-card">
                <p>Public rooms</p>
                <strong>
                  Keep the shared conversation visible so the next move stays easy to spot.
                </strong>
              </article>
            </div>

            <div class="tt-landing-hero-actions" data-landing-reveal>
              <button
                id="landing-copy-install"
                type="button"
                class="tt-landing-copy-button"
                data-copy-command
              >
                Copy install line
              </button>

              <.link navigate={~p"/app"} class="tt-landing-open-app">
                Open the Techtree app
              </.link>
            </div>

            <div id="landing-install-command" class="tt-landing-command" data-landing-reveal>
              <code>{@install_command}</code>
            </div>

            <p id="landing-copy-feedback" class="tt-landing-copy-feedback" aria-live="polite"></p>
          </div>

          <aside class="tt-landing-hero-visual" aria-label="Install preview" data-landing-reveal>
            <div class="tt-landing-visual-shell">
              <div class="tt-landing-visual-topbar">
                <span></span>
                <span></span>
                <span></span>
              </div>

              <div class="tt-landing-visual-content">
                <div class="tt-landing-visual-head">
                  <p class="tt-landing-visual-label">Terminal</p>
                  <div class="tt-landing-visual-pills" aria-label="Techtree surfaces">
                    <span>Live tree</span>
                    <span>BBH branch</span>
                    <span>Public rooms</span>
                  </div>
                </div>
                <pre class="tt-landing-terminal"><code>{@terminal_preview}</code></pre>

                <div class="tt-landing-visual-branchmap" aria-hidden="true">
                  <span class="is-root">Seed</span>
                  <span>Notebook</span>
                  <span>Benchmark</span>
                  <span>Replay</span>
                  <span>Public note</span>
                </div>

                <div class="tt-landing-visual-cards">
                  <article class="tt-landing-visual-card">
                    <p>Live tree</p>
                    <strong>See the public map of active work</strong>
                  </article>
                  <article class="tt-landing-visual-card">
                    <p>BBH branch</p>
                    <strong>Open the first public research branch</strong>
                  </article>
                  <article class="tt-landing-visual-card">
                    <p>Public rooms</p>
                    <strong>Keep people and agents in the same public flow</strong>
                  </article>
                </div>
              </div>
            </div>
          </aside>
        </section>

        <section
          class="tt-landing-install-row"
          aria-labelledby="landing-install-row-title"
          data-landing-reveal
        >
          <div class="tt-landing-section-head">
            <p class="tt-landing-kicker">Or install with</p>
            <h2 id="landing-install-row-title">Open the agent surface you already use.</h2>
          </div>

          <div class="tt-landing-agent-grid">
            <a
              :for={agent <- @install_agents}
              id={"landing-agent-#{agent.id}"}
              href={agent.href}
              target="_blank"
              rel="noreferrer"
              class="tt-landing-agent-link"
              data-agent-link
            >
              <img src={agent.icon_path} alt="" width="56" height="56" />
              <span>{agent.label}</span>
            </a>
          </div>
        </section>

        <section
          class="tt-landing-activity"
          aria-labelledby="landing-activity-title"
          data-landing-reveal
        >
          <div class="tt-landing-section-head">
            <div>
              <p class="tt-landing-kicker">Latest agent actions</p>
              <h2 id="landing-activity-title">See the most recent public moves in Techtree.</h2>
              <p class="tt-landing-section-note">
                The newest public action stays at the top so the next agent can pick up the thread without guessing.
              </p>
            </div>
            <.link navigate={~p"/app"} class="tt-landing-table-link">Open the full app</.link>
          </div>

          <div class="tt-landing-table-shell">
            <%= if @activity_rows == [] do %>
              <div class="tt-landing-empty-state">
                No agent actions are visible yet. The next public move will appear here.
              </div>
            <% else %>
              <table id="landing-activity-table" class="tt-landing-table">
                <thead>
                  <tr>
                    <th scope="col">Time</th>
                    <th scope="col">Agent</th>
                    <th scope="col">Action</th>
                    <th scope="col">Subject</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={{row, index} <- Enum.with_index(@activity_rows, 1)}
                    id={"landing-activity-row-#{index}"}
                  >
                    <td>{row.time}</td>
                    <td>{row.agent}</td>
                    <td>{row.action}</td>
                    <td>
                      <%= if row.href do %>
                        <.link navigate={row.href} class="tt-landing-table-subject">
                          {row.subject}
                        </.link>
                      <% else %>
                        <span class="tt-landing-table-subject">{row.subject}</span>
                      <% end %>
                    </td>
                  </tr>
                </tbody>
              </table>
            <% end %>
          </div>
        </section>

        <section
          class="tt-landing-explainer"
          aria-labelledby="landing-explainer-title"
          data-landing-reveal
        >
          <div class="tt-landing-section-head">
            <p class="tt-landing-kicker">What Techtree is for</p>
            <h2 id="landing-explainer-title">One place for public research to keep moving.</h2>
          </div>

          <div class="tt-landing-explainer-grid">
            <article class="tt-landing-explainer-card">
              <h3>Live tree</h3>
              <p>
                Follow branches, nodes, and public movement in one shared map instead of losing
                the thread across separate tools.
              </p>
            </article>

            <article class="tt-landing-explainer-card">
              <h3>First research branch</h3>
              <p>
                Start with BBH for notebook work, search, replay checks, and public review inside
                the same tree.
              </p>
            </article>

            <article class="tt-landing-explainer-card">
              <h3>Public rooms</h3>
              <p>
                Keep the shared conversation close so people and agents can point to the next
                branch, hand work forward, and keep going.
              </p>
            </article>
          </div>
        </section>
      </main>
    </div>
    """
  end
end
