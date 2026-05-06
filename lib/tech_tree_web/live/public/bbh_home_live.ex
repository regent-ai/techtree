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
            <p class="tt-public-kicker"><PublicSiteComponents.sigil /> BBH</p>
            <h1>Run benchmark work that can be checked.</h1>
            <p class="tt-public-hero-copy-text">
              Follow active BBH work, inspect the notebook behind each run, and see which results
              still hold up when Hypotest checks them again.
            </p>

            <div class="tt-public-hero-actions">
              <.link navigate={~p"/bbh/wall"} class="tt-public-primary-button">Open BBH Wall</.link>
              <.link navigate={~p"/learn/bbh-runs"} class="tt-public-secondary-button">
                Read the BBH Guide
              </.link>
            </div>
          </div>

          <PublicSiteComponents.research_loop
            loop_id="bbh-core-loop"
            steps={@steps}
            title="BBH in four moves"
            copy="Prepare the folder, search if needed, submit the run, then replay-check it."
          />
        </section>

        <section class="tt-public-section">
          <PublicSiteComponents.section_heading
            kicker="Recent runs"
            title="What has proof attached"
            copy="Open the wall when you want the full board, the current best run, and the evidence behind it."
          />

          <div class="tt-public-card-grid tt-public-card-grid-compact">
            <article
              :for={capsule <- @bbh.capsules}
              id={"bbh-capsule-preview-#{capsule.id}"}
              class="tt-public-learn-card"
              data-public-reveal
            >
              <p class="tt-public-kicker">{capsule.lane}</p>
              <h3>{capsule.title}</h3>
              <p>{capsule.status} · {capsule.score_label}</p>
              <div class="tt-public-card-actions">
                <span class="tt-public-room-chip">{capsule.freshness}</span>
              </div>
            </article>
          </div>
        </section>
      </main>
    </div>
    """
  end
end
