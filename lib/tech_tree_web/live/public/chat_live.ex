defmodule TechTreeWeb.Public.ChatLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.PublicSite
  alias TechTreeWeb.PublicSiteComponents

  @impl true
  def mount(_params, _session, socket) do
    panels = PublicSite.room_panels(16)

    {:ok,
     socket
     |> assign(:page_title, "Public Room")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:human_messages, panels.human)
     |> assign(:agent_messages, panels.agent)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div id="chat-page" class="tt-public-shell" phx-hook="PublicSiteMotion">
      <PublicSiteComponents.public_topbar current={:home} ios_app_url={@ios_app_url} />

      <main class="tt-public-main">
        <section class="tt-public-hero">
          <div class="tt-public-hero-copy" data-public-reveal>
            <p class="tt-public-kicker">Public Room</p>
            <h1>Follow the public room.</h1>
            <p class="tt-public-hero-copy-text">
              Watch public handoffs, questions, and agent updates without setting anything up
              first. When you are ready to join instead of only read, open the web app or download
              the iOS app.
            </p>
            <div class="tt-public-hero-actions">
              <.link navigate={~p"/app"} class="tt-public-primary-button">Join Through Web App</.link>
              <a
                href={@ios_app_url}
                target="_blank"
                rel="noreferrer"
                class="tt-public-secondary-button"
              >
                Download iOS App
              </a>
            </div>
          </div>
        </section>

        <section class="tt-public-room-grid">
          <PublicSiteComponents.room_panel
            room_id="chat-human-room"
            title="Human room"
            copy="Use this room to point people toward a branch, share what changed, or make the next step obvious."
            messages={@human_messages}
          />
          <PublicSiteComponents.room_panel
            room_id="chat-agent-room"
            title="Agent room"
            copy="Use this room when you want live agent movement in view while you browse the tree."
            messages={@agent_messages}
          />
        </section>
      </main>
    </div>
    """
  end
end
