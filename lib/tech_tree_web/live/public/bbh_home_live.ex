defmodule TechTreeWeb.Public.BbhHomeLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.PublicSite
  alias TechTreeWeb.PublicSiteComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "BBH")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:steps, PublicSite.bbh_flow_steps())
     |> assign(:bbh, PublicSite.bbh_snapshot())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div id="bbh-home-page" class="tt-public-shell" phx-hook="PublicSiteMotion">
      <PublicSiteComponents.public_topbar current={:bbh} ios_app_url={@ios_app_url} />

      <main class="tt-public-main">
        <section class="tt-public-hero tt-public-hero-split">
          <div class="tt-public-hero-copy" data-public-reveal>
            <p class="tt-public-kicker">BBH</p>
            <h1>Benchmark and research work in public.</h1>
            <p class="tt-public-hero-copy-text">
              Follow active BBH work, see what held up in replay, and understand how notebooks
              become public runs. BBH is the clearest public research branch in Techtree today.
            </p>

            <div class="tt-public-hero-actions">
              <.link navigate={~p"/bbh/wall"} class="tt-public-primary-button">Open BBH Wall</.link>
              <.link navigate={~p"/learn/bbh-train"} class="tt-public-secondary-button">
                Read the BBH Guide
              </.link>
            </div>
          </div>

          <aside class="tt-public-signal-panel" data-public-reveal>
            <PublicSiteComponents.section_heading
              kicker="Live snapshot"
              title="What is moving right now"
              copy="These counts update from the live public BBH board."
            />
            <dl class="tt-public-node-stats tt-public-node-stats-large">
              <div>
                <dt>Practice</dt>
                <dd>{@bbh.lane_counts.practice}</dd>
              </div>
              <div>
                <dt>Proving</dt>
                <dd>{@bbh.lane_counts.proving}</dd>
              </div>
              <div>
                <dt>Challenge</dt>
                <dd>{@bbh.lane_counts.challenge}</dd>
              </div>
              <div>
                <dt>Top validated</dt>
                <dd>{Float.round(@bbh.top_score, 1)}%</dd>
              </div>
            </dl>
          </aside>
        </section>

        <section class="tt-public-section">
          <div class="tt-public-learn-layout">
            <div class="tt-public-learn-main">
              <PublicSiteComponents.section_heading
                kicker="Recent Runs"
                title="Public capsules on the board"
                copy="Open the wall when you want the full live board and the pinned drilldown."
              />

              <div class="tt-public-card-grid">
                <article
                  :for={capsule <- @bbh.capsules}
                  id={"bbh-capsule-preview-#{capsule.id}"}
                  class="tt-public-learn-card"
                  data-public-reveal
                >
                  <p class="tt-public-kicker">{capsule.lane}</p>
                  <h3>{capsule.title}</h3>
                  <p>{capsule.status}</p>
                  <ul class="tt-public-bullet-list">
                    <li>Best score: {capsule.score_label}</li>
                    <li>Freshness: {capsule.freshness}</li>
                  </ul>
                </article>
              </div>
            </div>

            <aside class="tt-public-learn-side">
              <PublicSiteComponents.step_rail rail_id="bbh-flow-rail" steps={@steps} />
            </aside>
          </div>
        </section>
      </main>
    </div>
    """
  end
end
