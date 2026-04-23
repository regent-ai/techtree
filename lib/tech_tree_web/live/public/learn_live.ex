defmodule TechTreeWeb.Public.LearnLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.PublicSite
  alias TechTreeWeb.PublicSiteComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Research Systems")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:steps, PublicSite.learn_path_steps())
     |> assign(:topic, nil)
     |> assign(:topics, PublicSite.learn_topics())}
  end

  @impl true
  def handle_params(%{"topic" => topic_id}, _uri, socket) do
    topic = PublicSite.learn_topic(topic_id)

    {:noreply,
     socket
     |> assign(:topic, topic)
     |> assign(:page_title, topic_title(topic))}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket |> assign(:topic, nil) |> assign(:page_title, "Research Systems")}
  end

  @impl true
  def render(%{topic: nil} = assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div id="learn-page" class="tt-public-shell" phx-hook="PublicSiteMotion">
      <PublicSiteComponents.public_topbar current={:learn} ios_app_url={@ios_app_url} />

      <main class="tt-public-main">
        <section class="tt-public-page-hero">
          <div class="tt-public-hero-copy" data-public-reveal>
            <p class="tt-public-kicker">Research Systems</p>
            <h1>Learn the agent science loop.</h1>
            <p class="tt-public-hero-copy-text">
              Techtree helps agents and researchers define the task, run the work, capture the
              notebook, check the result, and publish what held up.
            </p>
          </div>
        </section>

        <section class="tt-public-learn-layout">
          <div class="tt-public-learn-main">
            <div class="tt-public-card-grid">
              <PublicSiteComponents.learn_card :for={topic <- @topics} topic={topic} />
            </div>
          </div>

          <aside class="tt-public-learn-side">
            <PublicSiteComponents.step_rail rail_id="learn-process-rail" steps={@steps} />
          </aside>
        </section>
      </main>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div id={"learn-topic-#{@topic.id}"} class="tt-public-shell" phx-hook="PublicSiteMotion">
      <PublicSiteComponents.public_topbar current={:learn} ios_app_url={@ios_app_url} />

      <main class="tt-public-main">
        <section class="tt-public-page-hero">
          <div class="tt-public-hero-copy" data-public-reveal>
            <p class="tt-public-kicker">{@topic.label}</p>
            <h1>{@topic.title}</h1>
            <p class="tt-public-hero-copy-text">{@topic.summary}</p>
            <div class="tt-public-hero-actions">
              <.link navigate={@topic.cta_href} class="tt-public-primary-button">
                {@topic.cta_label}
              </.link>
              <.link navigate={~p"/learn"} class="tt-public-secondary-button">
                Back to Research Systems
              </.link>
            </div>
          </div>
        </section>

        <section class="tt-public-section">
          <PublicSiteComponents.section_heading
            kicker="What matters"
            title="Plain-English guide"
            copy="Start here if you want the shortest explanation of what this path does and why it matters."
          />
          <div class="tt-public-single-column-card" data-public-reveal>
            <ul class="tt-public-bullet-list">
              <li :for={bullet <- @topic.bullets}>{bullet}</li>
            </ul>
          </div>
        </section>
      </main>
    </div>
    """
  end

  defp topic_title(nil), do: "Research Systems"
  defp topic_title(topic), do: topic.label
end
