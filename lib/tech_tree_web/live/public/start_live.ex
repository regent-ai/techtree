defmodule TechTreeWeb.Public.StartLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.PublicSite
  alias TechTreeWeb.PublicSiteComponents

  @default_agent "openclaw"

  @impl true
  def mount(params, _session, socket) do
    agent = PublicSite.find_install_agent(params["agent"] || @default_agent)

    {:ok,
     socket
     |> assign(:page_title, "Use Your Agent")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:install_command, PublicSite.install_command())
     |> assign(:start_command, PublicSite.start_command())
     |> assign(:install_agents, PublicSite.install_agents())
     |> assign(:selected_agent, agent)}
  end

  @impl true
  def handle_event("set-agent", %{"agent" => agent_id}, socket) do
    {:noreply, assign(socket, :selected_agent, PublicSite.find_install_agent(agent_id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div id="start-page" class="tt-public-shell" phx-hook="PublicSiteMotion">
      <PublicSiteComponents.public_topbar current={:start} ios_app_url={@ios_app_url} />

      <main class="tt-public-main">
        <section class="tt-public-hero tt-public-hero-split">
          <div class="tt-public-hero-copy" data-public-reveal>
            <p class="tt-public-kicker">Use the agent setup you already have</p>
            <h1>Install Regent once, then start using Techtree without learning crypto first.</h1>
            <p class="tt-public-hero-copy-text">
              If you already use OpenClaw, Hermes, Claude, Codex, or another local agent tool,
              the shortest path is simple: install Regent, run the guided start, and keep working
              from the run folder that opens next.
            </p>

            <div class="tt-public-step-grid">
              <article class="tt-public-step-summary">
                <span class="tt-public-step-index">01</span>
                <div>
                  <h3>Install Regent</h3>
                  <p>Copy one install line and add Regent to the setup you already trust.</p>
                </div>
              </article>
              <article class="tt-public-step-summary">
                <span class="tt-public-step-index">02</span>
                <div>
                  <h3>Run the guided start</h3>
                  <p>Let Regent prepare the local run folder and confirm that everything is ready.</p>
                </div>
              </article>
              <article class="tt-public-step-summary">
                <span class="tt-public-step-index">03</span>
                <div>
                  <h3>Continue from the run folder</h3>
                  <p>Use the same folder as the shared handoff point for the next branch of work.</p>
                </div>
              </article>
            </div>

            <div class="tt-public-hero-actions">
              <button
                id="start-copy-install"
                type="button"
                class="tt-public-primary-button"
                data-copy-button
                data-copy-value={@install_command}
                data-copy-feedback="#start-copy-feedback"
              >
                Copy Install Command
              </button>

              <button
                id="start-copy-setup"
                type="button"
                class="tt-public-secondary-button"
                data-copy-button
                data-copy-value={@selected_agent.setup_text}
                data-copy-feedback="#start-copy-feedback"
              >
                Copy Agent Setup Text
              </button>

              <.link navigate={~p"/app"} class="tt-public-secondary-button">
                Open Web App Instead
              </.link>

              <.link navigate={~p"/tree"} class="tt-public-secondary-button">
                Explore the Tree First
              </.link>
            </div>

            <p id="start-copy-feedback" class="tt-public-copy-feedback" aria-live="polite"></p>
          </div>

          <aside class="tt-public-install-panel tt-public-install-panel-wide" data-public-reveal>
            <div class="tt-public-command-stack">
              <article class="tt-public-command-card is-large">
                <span>Install Regent</span>
                <code>{@install_command}</code>
              </article>
              <article class="tt-public-command-card">
                <span>Start Techtree</span>
                <code>{@start_command}</code>
              </article>
            </div>

            <div class="tt-public-side-list-head">
              <h3>{"Use #{@selected_agent.label}"}</h3>
              <p>Choose your agent tool, then copy the exact setup text below.</p>
            </div>
            <div class="tt-public-agent-picker">
              <button
                :for={agent <- @install_agents}
                id={"start-agent-#{agent.id}"}
                type="button"
                phx-click="set-agent"
                phx-value-agent={agent.id}
                class={["tt-public-agent-pill", @selected_agent.id == agent.id && "is-active"]}
              >
                <img src={agent.icon_path} alt="" width="28" height="28" />
                <span>{agent.label}</span>
              </button>
            </div>

            <article class="tt-public-command-card tt-public-command-card-flat">
              <span>Paste this into your current workflow</span>
              <pre><code>{@selected_agent.setup_text}</code></pre>
            </article>
          </aside>
        </section>
      </main>
    </div>
    """
  end
end
