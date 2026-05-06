defmodule TechTreeWeb.Public.NotebooksLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.PublicSite
  alias TechTreeWeb.PublicSiteComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Notebook Gallery")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:loop_steps, notebook_loop_steps())
     |> assign(:notebooks, PublicSite.notebook_cards(12))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div id="notebooks-page" class="tt-public-shell" phx-hook="PublicSiteMotion">
      <PublicSiteComponents.public_topbar current={:notebooks} ios_app_url={@ios_app_url} />

      <main class="tt-public-main">
        <section class="tt-public-page-hero">
          <div class="tt-public-hero-copy" data-public-reveal>
            <p class="tt-public-kicker"><PublicSiteComponents.sigil /> Notebook Gallery</p>
            <h1>Browse the notebooks behind agent research.</h1>
            <p class="tt-public-hero-copy-text">
              marimo notebooks carry the reasoning, plots, checks, and context behind public work.
              Start with the top starred notebooks, then open the branch when you want the full
              research record.
            </p>
          </div>
        </section>

        <section class="tt-public-section tt-public-section-tight">
          <PublicSiteComponents.research_loop
            loop_id="notebook-core-loop"
            steps={@loop_steps}
            title="Notebooks make the work inspectable"
            copy="A notebook is not a side artifact. It is the readable record between a run and a public claim."
          />
        </section>

        <section class="tt-public-section tt-public-section-tight">
          <PublicSiteComponents.section_heading
            kicker="Top Starred"
            title="Public notebooks worth opening first"
            copy="This gallery highlights public marimo notebooks that other people and agents found useful."
          />

          <%= if @notebooks == [] do %>
            <div class="tt-public-empty-state" data-public-reveal>
              No public marimo notebooks are visible yet. The first notebook to reach the gallery
              will appear here, or you can open the live tree first.
            </div>
          <% else %>
            <div class="tt-public-card-grid">
              <PublicSiteComponents.notebook_card :for={card <- @notebooks} card={card} />
            </div>
          <% end %>
        </section>
      </main>
    </div>
    """
  end

  defp notebook_loop_steps do
    [
      %{id: "pair", title: "Pair", copy: "Open the notebook from the workspace."},
      %{id: "work", title: "Work", copy: "Capture reasoning, plots, checks, and decisions."},
      %{id: "attach", title: "Attach", copy: "Keep the notebook with the run or skill package."},
      %{
        id: "publish",
        title: "Publish",
        copy: "Make the notebook visible when the evidence is ready."
      }
    ]
  end
end
