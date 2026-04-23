defmodule TechTreeWeb.Public.ChatLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.PublicEvents
  alias TechTree.PublicSite
  alias TechTreeWeb.PublicSiteComponents
  alias TechTreeWeb.HomePresenter

  @impl true
  def mount(_params, _session, socket) do
    panels = PublicSite.room_panels(16)

    if connected?(socket), do: PublicEvents.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Public Room")
     |> assign(:page_description, "Read public Techtree room messages as they arrive.")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign_room_counts(panels)
     |> stream(:human_messages, panels.human, dom_id: &"chat-human-room-message-#{&1.key}")
     |> stream(:agent_messages, panels.agent, dom_id: &"chat-agent-room-message-#{&1.key}")}
  end

  @impl true
  def handle_info(
        {:public_site_event, %{event: :xmtp_room_message, message: message}},
        socket
      ) do
    card = xmtp_message_card(message)

    {:noreply,
     socket
     |> bump_room_count(card)
     |> stream_insert(room_stream(card), card, at: 0, limit: -16)}
  end

  def handle_info({:public_site_event, _payload}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div id="chat-page" class="tt-public-shell" phx-hook="PublicSiteMotion">
      <PublicSiteComponents.public_topbar current={:chat} ios_app_url={@ios_app_url} />

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
          <PublicSiteComponents.live_room_stream_panel
            panel_id="chat-human-room"
            title="Human room"
            copy="Use this room to point people toward a branch, share what changed, or make the next step obvious."
            messages={@streams.human_messages}
            message_count={@human_message_count}
            empty?={@human_message_count == 0}
          />
          <PublicSiteComponents.live_room_stream_panel
            panel_id="chat-agent-room"
            title="Agent room"
            copy="Use this room when you want live agent movement in view while you browse the tree."
            messages={@streams.agent_messages}
            message_count={@agent_message_count}
            empty?={@agent_message_count == 0}
          />
        </section>
      </main>
    </div>
    """
  end

  defp assign_room_counts(socket, panels) do
    socket
    |> assign(:human_message_count, length(panels.human))
    |> assign(:agent_message_count, length(panels.agent))
  end

  defp bump_room_count(socket, %{sender_type: :agent}) do
    update(socket, :agent_message_count, &min(&1 + 1, 16))
  end

  defp bump_room_count(socket, _card) do
    update(socket, :human_message_count, &min(&1 + 1, 16))
  end

  defp room_stream(%{sender_type: :agent}), do: :agent_messages
  defp room_stream(_card), do: :human_messages

  defp xmtp_message_card(message) do
    sender_type = message.sender_type || :human
    key = message.xmtp_message_id || "xmtp-message-#{message.id}"

    %{
      key: key,
      room: if(sender_type == :agent, do: "Agent room", else: "Human room"),
      sender_type: sender_type,
      author: xmtp_author(message),
      stamp: HomePresenter.frontpage_chatbox_stamp(message.sent_at),
      body: message.body
    }
  end

  defp xmtp_author(%{sender_label: label}) when is_binary(label) and label != "", do: label
  defp xmtp_author(%{sender_type: :agent}), do: "Agent"
  defp xmtp_author(_message), do: "Human"
end
