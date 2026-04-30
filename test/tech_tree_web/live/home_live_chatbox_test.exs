defmodule TechTreeWeb.HomeLiveChatboxTest do
  use TechTreeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TechTree.PhaseDApiSupport, only: [create_canonical_room!: 0, create_visible_message!: 2]

  alias TechTree.{PhaseDApiSupport, XMTPMirror}

  setup do
    %{room: create_canonical_room!()}
  end

  test "homepage chatbox shells stay in the chrome contract", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/app")

    assert has_element?(view, "#frontpage-agent-chatbox input[disabled]")
    assert has_element?(view, "#frontpage-agent-chatbox button[disabled]", "Read only")
    assert has_element?(view, "#frontpage-human-chatbox[data-privy-app-id]")

    assert has_element?(
             view,
             "#frontpage-human-chatbox[data-session-url='/api/auth/privy/session']"
           )

    assert has_element?(view, "#frontpage-human-chatbox[data-room-can-join]")
    assert has_element?(view, "#frontpage-human-chatbox[data-room-can-send]")

    assert has_element?(view, "#frontpage-human-chatbox [data-chatbox-auth]", "Sign in")
    assert has_element?(view, "#frontpage-human-chatbox [data-chatbox-state][role='status']")
    assert has_element?(view, "#frontpage-human-chatbox input[data-chatbox-input][disabled]")
    assert has_element?(view, "#frontpage-human-chatbox button[data-chatbox-send][disabled]")
    assert render(view) =~ "No live public posts yet."
    assert render(view) =~ "Agent chat"
    assert render(view) =~ "Human chat"
    assert render(view) =~ "public room"
    assert render(view) =~ "There are 200 seats in the first room."
  end

  test "homepage chatbox panels render shared public room messages by sender kind", %{
    conn: conn,
    room: room
  } do
    human_message =
      create_visible_message!(room, %{
        sender_type: :human,
        sender_label: "human sender",
        body: "human shared panel message"
      })

    agent_message =
      create_visible_message!(room, %{
        sender_type: :agent,
        sender_label: "agent sender",
        body: "agent shared panel message"
      })

    {:ok, view, _html} = live(conn, ~p"/app")

    assert has_element?(
             view,
             "#frontpage-agent-chatbox .chat-bubble",
             "agent shared panel message"
           )

    assert has_element?(
             view,
             "#frontpage-human-chatbox .chat-bubble",
             "human shared panel message"
           )

    assert has_element?(view, "#frontpage-agent-chatbox .chat-header", agent_message.sender_label)
    assert has_element?(view, "#frontpage-human-chatbox .chat-header", human_message.sender_label)
    refute render(view) =~ "<time class=\"ml-2 opacity-70\">-</time>"
  end

  test "homepage chatbox refreshes when the mirror receives a public room message", %{
    conn: conn,
    room: room
  } do
    {:ok, view, _html} = live(conn, ~p"/app")

    wallet = PhaseDApiSupport.random_eth_address()

    assert {:ok, _message} =
             XMTPMirror.ingest_message(%{
               "room_id" => room.id,
               "xmtp_message_id" => "homepage-live-message-#{PhaseDApiSupport.unique_suffix()}",
               "sender_inbox_id" => PhaseDApiSupport.deterministic_inbox_id(wallet),
               "sender_wallet_address" => wallet,
               "sender_label" => "live sender",
               "sender_type" => "human",
               "body" => "arrived after mount",
               "sent_at" => DateTime.utc_now(),
               "raw_payload" => %{"kind" => "message"},
               "moderation_state" => "visible"
             })

    assert render(view) =~ "arrived after mount"
  end
end
