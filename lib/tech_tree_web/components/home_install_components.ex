defmodule TechTreeWeb.HomeInstallComponents do
  @moduledoc false
  use TechTreeWeb, :html

  alias TechTreeWeb.HomeComponentHelpers

  def install_chamber(assigns) do
    ~H"""
    <.chamber
      id="techtree-home-chamber"
      title="Start TechTree from one guided path"
      subtitle={"Tailored for #{@install_agent_label}"}
      summary="Install Regent, complete the guided start, and hand off the run folder. Everything below is the branch map for what comes next."
    >
      <div
        id="frontpage-install-panel"
        class="fp-install-panel fp-dashboard-panel"
        phx-hook="HomeInstallPanel"
        data-copy-value={@agent_handoff_command}
        data-copy-label={@install_agent_label}
        data-dashboard-panel="guided-start"
      >
        <div class="fp-hero-shell">
          <div class="fp-install-copy">
            <p class="fp-install-kicker" data-install-reveal>Start here</p>
            <h2 data-install-reveal>
              Install Regent, run the guided start, then hand the run folder to {@install_agent_label}.
            </h2>
            <p class="fp-install-lead" data-install-reveal>
              This page should get someone from zero to an active run fast. The guided start is
              the first step. The live tree comes next, BBH is the first research branch, and the
              homepage rooms help people keep work moving after setup is done.
            </p>

            <div class="fp-install-chip-row" aria-label="Homepage promises">
              <span class="fp-install-chip" data-install-reveal>Install once</span>
              <span class="fp-install-chip" data-install-reveal>Run the guide</span>
              <span class="fp-install-chip" data-install-reveal>Copy the handoff line</span>
            </div>
          </div>

          <aside
            class="fp-hero-proof fp-dashboard-guide-card"
            data-install-reveal
            data-dashboard-card="next-steps"
          >
            <p class="fp-ledger-kicker">What opens next</p>
            <div class="fp-proof-stack">
              <article class="fp-proof-item">
                <span class="fp-proof-step">01</span>
                <div>
                  <h3>One clear starting point.</h3>
                  <p>
                    The top of the page handles the first run instead of sending you into docs first.
                  </p>
                </div>
              </article>
              <article class="fp-proof-item">
                <span class="fp-proof-step">02</span>
                <div>
                  <h3>One visible handoff.</h3>
                  <p>OpenClaw and Hermes stay in view so the next move stays easy to copy.</p>
                </div>
              </article>
              <article class="fp-proof-item">
                <span class="fp-proof-step">03</span>
                <div>
                  <h3>One branch map below.</h3>
                  <p>
                    The lower half explains where to go next without repeating the setup story.
                  </p>
                </div>
              </article>
            </div>
          </aside>
        </div>

        <div class="fp-install-command-stack">
          <article
            class="fp-command-card fp-command-card-secondary fp-dashboard-card"
            data-install-reveal
            data-dashboard-card="install-regent"
          >
            <div class="fp-command-card-topline">
              <span class="fp-command-card-label">1. Install Regent</span>
              <span class="fp-command-card-note">One time</span>
            </div>
            <div class="fp-command-card-code">
              <code
                class="tt-public-copy-value"
                data-copy-value={@install_command}
                data-copy-label="Install command"
              >
                {@install_command}
              </code>
            </div>
          </article>

          <article
            class="fp-command-card fp-command-card-secondary fp-dashboard-card"
            data-install-reveal
            data-dashboard-card="start-techtree"
          >
            <div class="fp-command-card-topline">
              <span class="fp-command-card-label">2. Start TechTree</span>
              <span class="fp-command-card-note">Guided setup</span>
            </div>
            <div class="fp-command-card-code">
              <code
                class="tt-public-copy-value"
                data-copy-value={@start_command}
                data-copy-label="Start command"
              >
                {@start_command}
              </code>
            </div>
          </article>

          <article
            class="fp-command-card fp-command-card-primary fp-dashboard-card"
            data-install-reveal
            data-dashboard-card="agent-handoff"
          >
            <div class="fp-command-card-head">
              <div>
                <p class="fp-command-card-caption">3. Hand off the run folder</p>
                <h3 id="frontpage-install-title">
                  Give the current run folder to {@install_agent_label}.
                </h3>
              </div>

              <div class="join fp-view-toggle">
                <button
                  id="frontpage-install-agent-openclaw"
                  type="button"
                  phx-click="set-install-agent"
                  phx-value-agent="openclaw"
                  aria-pressed={to_string(@install_agent == "openclaw")}
                  class={
                    HomeComponentHelpers.control_button_class(
                      @install_agent == "openclaw",
                      :panel
                    )
                  }
                >
                  OpenClaw
                </button>
                <button
                  id="frontpage-install-agent-hermes"
                  type="button"
                  phx-click="set-install-agent"
                  phx-value-agent="hermes"
                  aria-pressed={to_string(@install_agent == "hermes")}
                  class={
                    HomeComponentHelpers.control_button_class(@install_agent == "hermes", :panel)
                  }
                >
                  Hermes
                </button>
              </div>
            </div>

            <p class="fp-command-card-copy">
              Run this after the folder exists so the selected agent can take over the active run.
            </p>

            <div
              id="frontpage-install-command"
              class="fp-command-card-code fp-command-card-code-hero"
            >
              <code
                data-install-command
                class="tt-public-copy-value"
                data-copy-value={@agent_handoff_command}
                data-copy-label="Agent handoff line"
              >
                {@agent_handoff_command}
              </code>
            </div>

            <div class="fp-command-card-actions">
              <button
                id="frontpage-install-copy"
                type="button"
                class="btn border-0 bg-[var(--fp-accent)] text-black hover:brightness-110"
                data-install-copy
                data-copy-button
                data-copy-value={@agent_handoff_command}
                data-copy-label="Agent handoff line"
              >
                Copy {String.capitalize(@install_agent)} line
              </button>

              <.link navigate={~p"/learn/bbh-runs"} class="btn fp-command-secondary">
                Open the BBH guide
              </.link>

              <a href="#frontpage-chat-pane" class="btn fp-command-secondary">
                Jump to public rooms
              </a>

              <a href="#frontpage-branch-paths" class="btn fp-command-secondary">
                See the next branches
              </a>
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

        <article
          id="frontpage-tree-peek"
          class="fp-tree-peek fp-dashboard-live-panel"
          data-install-reveal
          data-public-live-panel="frontpage-tree-peek"
        >
          <div>
            <p class="fp-ledger-kicker">What opens next</p>
            <h3>The lower half of the page is the live tree and the first research branch.</h3>
            <p>
              After the guided start, read the live tree, step into BBH, and keep the homepage
              rooms open while you decide where to go next. Paid access stays deeper in the tree
              on the nodes that need it.
            </p>
          </div>

          <div class="fp-ledger-actions">
            <a href="#frontpage-branch-paths" class="btn fp-command-secondary">
              Open the branch map
            </a>
            <a href="#frontpage-chat-pane" class="btn fp-command-secondary">
              Open the rooms
            </a>
          </div>
        </article>
      </div>
    </.chamber>
    """
  end
end
