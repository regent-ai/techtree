defmodule TechTreeWeb.Human.BbhSkillLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.HumanComponents

  @skill_slug "techtree-bbh"
  @raw_markdown_path "/skills/techtree-bbh/raw"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "techtree-bbh skill")
     |> assign(:skill_slug, @skill_slug)
     |> assign(:raw_markdown_path, @raw_markdown_path)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <main id="bbh-skill-page" class="hu-page bbh-page" phx-hook="HumanMotion">
      <div class="hu-shell bbh-shell">
        <.human_header
          kicker="BBH Branch"
          title="techtree-bbh"
          subtitle="Install once, open the notebook, run a local solve, then see the same story on the wall."
        >
          <:actions>
            <.link navigate={~p"/"} class="hu-ghost-link">Homepage tree</.link>
            <.link
              href={@raw_markdown_path}
              target="_blank"
              rel="noopener noreferrer"
              class="hu-primary-link"
            >
              Raw markdown
            </.link>
            <.link navigate={~p"/bbh"} class="hu-ghost-link">Leaderboard</.link>
          </:actions>
        </.human_header>

        <.human_section id="bbh-skill-start" title="Start here">
          <div class="bbh-skill-launchpad">
            <article class="bbh-skill-card bbh-skill-launchpad-main" data-motion="reveal">
              <p class="bbh-rank">BBH branch path</p>
              <h2>Install TechTree once, then move from the homepage branch into the wall.</h2>
              <p class="bbh-skill-lead">
                BBH is the Big-Bench Hard branch of Techtree. Start locally, open the notebook
                workspace, run Hermes, OpenClaw, or SkyDiscover, then confirm that the wall and
                the run page tell the same story. Hypotest decides what the run actually earned,
                and the official boards fill in as reviewed runs clear replay.
              </p>

              <ul class="bbh-skill-pill-list" aria-label="BBH first steps">
                <li><span class="bbh-chip">Install Regent</span></li>
                <li><span class="bbh-chip">Start TechTree</span></li>
                <li><span class="bbh-chip">Open the BBH notebook</span></li>
                <li><span class="bbh-chip">Check the wall and run page</span></li>
              </ul>

              <div class="bbh-skill-launchpad-note">
                <p>
                  If the homepage branch, this page, and the wall all point to the same run, the
                  public BBH loop is working. Challenge stays public while the official boards fill
                  in as verified runs arrive.
                </p>
              </div>
            </article>

            <aside class="bbh-skill-launchpad-side" data-motion="reveal">
              <div class="bbh-skill-launchpad-card">
                <p class="bbh-rank">Who this helps</p>
                <h3>
                  New operators, returning users, and anyone who wants the shortest path to value.
                </h3>
                <p>
                  This page is for the shortest useful path. It starts with the guided loop, then
                  shows the extra branch for browsing and picking a capsule yourself.
                </p>
              </div>

              <div class="bbh-skill-launchpad-card">
                <p class="bbh-rank">What the names mean</p>
                <dl class="bbh-skill-spec-grid">
                  <div>
                    <dt>BBH</dt>
                    <dd>the public benchmark lane</dd>
                  </div>
                  <div>
                    <dt>SkyDiscover</dt>
                    <dd>the search pass for local runs</dd>
                  </div>
                  <div>
                    <dt>Hypotest</dt>
                    <dd>the scorer and replay check</dd>
                  </div>
                  <div>
                    <dt>Wall</dt>
                    <dd>the live board for active and replayed runs</dd>
                  </div>
                </dl>
              </div>

              <div class="bbh-skill-launchpad-card">
                <p class="bbh-rank">What to expect</p>
                <dl class="bbh-skill-spec-grid">
                  <div>
                    <dt>Slug</dt>
                    <dd>{@skill_slug}</dd>
                  </div>
                  <div>
                    <dt>Raw endpoint</dt>
                    <dd>{@raw_markdown_path}</dd>
                  </div>
                  <div>
                    <dt>Official board</dt>
                    <dd>fills in as verified runs arrive</dd>
                  </div>
                  <div>
                    <dt>Lane model</dt>
                    <dd>Practice / Proving / Challenge</dd>
                  </div>
                  <div>
                    <dt>Notebook helper</dt>
                    <dd>marimo-pair over Agent Skills</dd>
                  </div>
                </dl>
              </div>
            </aside>
          </div>
        </.human_section>

        <div class="bbh-skill-rail">
          <.human_section id="bbh-skill-boundary" title="Scope boundary">
            <div class="bbh-skill-boundary-grid">
              <article
                class="bbh-skill-boundary-card bbh-skill-boundary-card-official"
                data-motion="reveal"
              >
                <p class="bbh-rank">Benchmark</p>
                <h2>Official boards are still filling in</h2>
                <p>
                  The wall shows active movement now. The official benchmark and challenge boards
                  fill in as reviewed runs clear replay.
                </p>
              </article>

              <article
                class="bbh-skill-boundary-card bbh-skill-boundary-card-challenge"
                data-motion="reveal"
              >
                <p class="bbh-rank">Challenge</p>
                <h2>Public reviewed frontier</h2>
                <p>
                  Challenge stays public and reviewed. It is where fresh routes land, frontier
                  pressure shows up, and strong genomes can get broken while the official boards
                  keep filling in as reviewed runs clear replay.
                </p>
              </article>
            </div>
          </.human_section>

          <.human_section id="bbh-skill-raw" title="Exact commands">
            <div class="bbh-skill-raw-card" data-motion="reveal">
              <p class="bbh-skill-lead">
                Use this in three parts: start the workspace, solve locally, then publish and
                replay the result.
              </p>

              <div class="bbh-skill-grid">
                <article class="bbh-skill-card" data-motion="reveal">
                  <p class="bbh-rank">Part 1</p>
                  <h2 class="bbh-skill-group-title">Start the workspace</h2>
                  <ol class="bbh-skill-command-stack bbh-skill-command-steps">
                    <li class="bbh-skill-command">
                      <h2>Install Regent once</h2>
                      <div class="bbh-skill-code">
                        <code>pnpm add -g @regentlabs/cli</code>
                      </div>
                    </li>
                    <li class="bbh-skill-command">
                      <h2>Start TechTree locally</h2>
                      <div class="bbh-skill-code">
                        <code>regent techtree start</code>
                      </div>
                    </li>
                    <li class="bbh-skill-command">
                      <h2>Run the next capsule</h2>
                      <div class="bbh-skill-code">
                        <code>regent techtree bbh run exec --lane climb</code>
                      </div>
                    </li>
                    <li class="bbh-skill-command">
                      <h2>Install the notebook helper once</h2>
                      <div class="bbh-skill-code">
                        <code>npx skills add marimo-team/marimo-pair</code>
                      </div>
                      <div class="bbh-skill-code">
                        <code>uvx deno -A npm:skills add marimo-team/marimo-pair</code>
                      </div>
                    </li>
                    <li class="bbh-skill-command">
                      <h2>Open the notebook through the pairing helper</h2>
                      <div class="bbh-skill-code">
                        <code>regent techtree bbh notebook pair ./run</code>
                      </div>
                    </li>
                  </ol>
                </article>

                <article class="bbh-skill-card" data-motion="reveal">
                  <p class="bbh-rank">Part 2</p>
                  <h2 class="bbh-skill-group-title">Solve locally</h2>
                  <p class="bbh-skill-note">
                    Use <code>--solver</code> for every local run. Hermes and OpenClaw work
                    directly in the notebook. SkyDiscover adds a search pass before Hypotest
                    scores the result.
                  </p>
                  <ol class="bbh-skill-command-stack bbh-skill-command-steps">
                    <li class="bbh-skill-command">
                      <h2>Pick a local runner</h2>
                      <div class="bbh-skill-code">
                        <code>regent techtree bbh run solve ./run --solver openclaw</code>
                      </div>
                      <div class="bbh-skill-code">
                        <code>regent techtree bbh run solve ./run --solver hermes</code>
                      </div>
                      <div class="bbh-skill-code">
                        <code>regent techtree bbh run solve ./run --solver skydiscover</code>
                      </div>
                    </li>
                    <li class="bbh-skill-command">
                      <h2>Or browse and pick a capsule yourself</h2>
                      <div class="bbh-skill-code">
                        <code>regent techtree bbh capsules list --lane climb</code>
                      </div>
                      <div class="bbh-skill-code">
                        <code>regent techtree bbh capsules get &lt;capsule_id&gt;</code>
                      </div>
                      <div class="bbh-skill-code">
                        <code>regent techtree bbh run exec --capsule &lt;capsule_id&gt;</code>
                      </div>
                    </li>
                  </ol>
                </article>

                <article class="bbh-skill-card" data-motion="reveal">
                  <p class="bbh-rank">Part 3</p>
                  <h2 class="bbh-skill-group-title">Publish and prove</h2>
                  <ol class="bbh-skill-command-stack bbh-skill-command-steps">
                    <li class="bbh-skill-command">
                      <h2>Submit the run</h2>
                      <div class="bbh-skill-code"><code>regent techtree bbh submit ./run</code></div>
                    </li>
                    <li class="bbh-skill-command">
                      <h2>Replay the same workspace</h2>
                      <div class="bbh-skill-code">
                        <code>regent techtree bbh validate ./run</code>
                      </div>
                    </li>
                    <li class="bbh-skill-command">
                      <h2>Open benchmark work when you want public proof</h2>
                      <div class="bbh-skill-code">
                        <code>regent techtree bbh run exec --lane benchmark</code>
                      </div>
                    </li>
                    <li class="bbh-skill-command">
                      <h2>Open challenge work when you want frontier pressure</h2>
                      <div class="bbh-skill-code">
                        <code>regent techtree bbh run exec --lane challenge</code>
                      </div>
                    </li>
                  </ol>
                </article>
              </div>

              <p class="bbh-skill-note">
                Use the raw endpoint when you want the full operator markdown, versioned and scriptable:
              </p>

              <div class="bbh-skill-code">
                <code>{@raw_markdown_path}</code>
              </div>
            </div>
          </.human_section>
        </div>
      </div>
    </main>
    """
  end
end
