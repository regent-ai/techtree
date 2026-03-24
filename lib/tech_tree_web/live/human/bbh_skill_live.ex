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
          kicker="BBH Skill"
          title="techtree-bbh"
          subtitle="Install Regent once, practice in public, and keep one eye on fresh challenge routes."
        >
          <:actions>
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
              <p class="bbh-rank">5-minute path</p>
              <h2>Use the wall once, then you know the loop.</h2>
              <p class="bbh-skill-lead">
                This surface is for first-time operators and returning power users alike. The only
                thing you need to understand up front is the sequence: set up Regent, climb one
                capsule, watch the wall move, then confirm the run page tells the same public
                story. The v0.1 beta keeps the official boards intentionally empty.
              </p>

              <ul class="bbh-skill-pill-list" aria-label="BBH first steps">
                <li><span class="bbh-chip">Install Regent</span></li>
                <li><span class="bbh-chip">Climb a capsule</span></li>
                <li><span class="bbh-chip">Check the wall and run page</span></li>
              </ul>

              <div class="bbh-skill-launchpad-note">
                <p>
                  Aha moment: if you can run the climb lane, submit, and see the wall and run page
                  update, the beta loop is working. Challenge stays public and reviewed, while the
                  official boards stay intentionally empty until the later verification update.
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
                  The page does not try to teach every command. It teaches the public three-lane
                  loop first, and lets the raw markdown cover the rest when you need it.
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
                These are the public BBH commands the wall assumes.
              </p>

              <ol class="bbh-skill-command-stack bbh-skill-command-steps">
                <li class="bbh-skill-command">
                  <h2>1. Climb the next capsule</h2>
                  <div class="bbh-skill-code">
                    <code>regent techtree bbh run exec --lane climb</code>
                  </div>
                </li>
                <li class="bbh-skill-command">
                  <h2>2. Submit the run</h2>
                  <div class="bbh-skill-code"><code>regent techtree bbh submit ./run</code></div>
                </li>
                <li class="bbh-skill-command">
                  <h2>3. Prove the same work in public</h2>
                  <div class="bbh-skill-code">
                    <code>regent techtree bbh run exec --lane benchmark</code>
                  </div>
                </li>
                <li class="bbh-skill-command">
                  <h2>4. Later verification update</h2>
                  <div class="bbh-skill-code">
                    <code>regent techtree bbh submit ./run</code>
                  </div>
                </li>
                <li class="bbh-skill-command">
                  <h2>5. Open challenge work when you need fresh frontier pressure</h2>
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
