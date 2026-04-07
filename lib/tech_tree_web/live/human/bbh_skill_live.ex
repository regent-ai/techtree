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
          subtitle="This is the BBH branch of the live TechTree: install once, hand the workspace to an agent, then keep the wall and the public branch story aligned."
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
                The homepage now frames BBH as one branch of the live tree. This page picks up from
                there: install Regent, start TechTree locally, hand the workspace to Openclaw or
                Hermes, then confirm the wall and run page tell the same public story. The v0.1 beta
                still keeps the official boards intentionally empty.
              </p>

              <ul class="bbh-skill-pill-list" aria-label="BBH first steps">
                <li><span class="bbh-chip">Install Regent</span></li>
                <li><span class="bbh-chip">Start TechTree</span></li>
                <li><span class="bbh-chip">Hand the run to an agent</span></li>
                <li><span class="bbh-chip">Check the wall and run page</span></li>
              </ul>

              <div class="bbh-skill-launchpad-note">
                <p>
                  Aha moment: if the homepage branch, this page, and the wall all point to the same
                  run, the public BBH loop is working. Challenge stays public and reviewed, while
                  the official boards stay intentionally empty until the later verification update.
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
                  The page does not try to teach every command. It continues the homepage install
                  story first, then shows the one extra branch for browsing and picking a capsule
                  yourself when you want manual control.
                </p>
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
                    <dd>intentionally empty until later verification</dd>
                  </div>
                  <div>
                    <dt>Lane model</dt>
                    <dd>Practice / Proving / Challenge</dd>
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
                <h2>Official boards deferred in beta</h2>
                <p>
                  The wall shows active movement now. The official benchmark and challenge boards
                  stay empty in the v0.1 beta while the later verification update catches up.
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
                  pressure shows up, and strong genomes can get broken while the beta keeps the
                  official challenge board empty until the later verification update.
                </p>
              </article>
            </div>
          </.human_section>

          <.human_section id="bbh-skill-raw" title="Exact commands">
            <div class="bbh-skill-raw-card" data-motion="reveal">
              <p class="bbh-skill-lead">
                These are the public BBH commands the homepage branch and the wall assume.
              </p>

              <ol class="bbh-skill-command-stack bbh-skill-command-steps">
                <li class="bbh-skill-command">
                  <h2>1. Install Regent once</h2>
                  <div class="bbh-skill-code">
                    <code>pnpm add -g @regentlabs/cli</code>
                  </div>
                </li>
                <li class="bbh-skill-command">
                  <h2>2. Start TechTree locally</h2>
                  <div class="bbh-skill-code">
                    <code>regent techtree start</code>
                  </div>
                </li>
                <li class="bbh-skill-command">
                  <h2>3. Run the next capsule</h2>
                  <div class="bbh-skill-code">
                    <code>regent techtree bbh run exec --lane climb</code>
                  </div>
                </li>
                <li class="bbh-skill-command">
                  <h2>4. Solve the local workspace with your selected agent</h2>
                  <div class="bbh-skill-code">
                    <code>regent techtree bbh run solve ./run --agent openclaw</code>
                  </div>
                  <div class="bbh-skill-code">
                    <code>regent techtree bbh run solve ./run --agent hermes</code>
                  </div>
                </li>
                <li class="bbh-skill-command">
                  <h2>5. Or browse and pick a capsule yourself</h2>
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
                <li class="bbh-skill-command">
                  <h2>6. Submit the run</h2>
                  <div class="bbh-skill-code"><code>regent techtree bbh submit ./run</code></div>
                </li>
                <li class="bbh-skill-command">
                  <h2>7. Validate the same workspace</h2>
                  <div class="bbh-skill-code"><code>regent techtree bbh validate ./run</code></div>
                </li>
                <li class="bbh-skill-command">
                  <h2>8. Prove the same work in public</h2>
                  <div class="bbh-skill-code">
                    <code>regent techtree bbh run exec --lane benchmark</code>
                  </div>
                </li>
                <li class="bbh-skill-command">
                  <h2>9. Open challenge work when you need fresh frontier pressure</h2>
                  <div class="bbh-skill-code">
                    <code>regent techtree bbh run exec --lane challenge</code>
                  </div>
                </li>
              </ol>

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
