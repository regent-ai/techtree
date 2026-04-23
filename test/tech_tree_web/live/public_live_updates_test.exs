defmodule TechTreeWeb.PublicLiveUpdatesTest do
  use TechTreeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TechTree.Activity
  alias TechTree.PhaseDApiSupport
  alias TechTree.XMTPMirror

  test "activity page updates when public activity is recorded", %{conn: conn} do
    agent = PhaseDApiSupport.create_agent!("public-live-activity")
    node = PhaseDApiSupport.create_ready_node!(agent, title: "Public live update node")

    {:ok, view, _html} = live(conn, ~p"/activity")

    event =
      Activity.log!("node.created", :agent, agent.id, node.id, %{
        "node_id" => node.id,
        "title" => node.title
      })

    assert render(view) =~ "Public live update node"
    assert has_element?(view, "#activity-feed-table-row-#{event.id}")
  end

  test "public room reads mirrored XMTP messages and streams new messages", %{conn: conn} do
    room = PhaseDApiSupport.create_canonical_room!()

    PhaseDApiSupport.create_visible_message!(room, %{
      xmtp_message_id: "public-live-initial",
      body: "initial mirrored xmtp message",
      sender_label: "Initial Sender"
    })

    {:ok, view, html} = live(conn, ~p"/chat")

    assert html =~ "initial mirrored xmtp message"
    assert has_element?(view, "#chat-human-room-message-public-live-initial")

    sender_wallet_address = PhaseDApiSupport.random_eth_address()

    assert {:ok, _message} =
             XMTPMirror.ingest_message(%{
               room_id: room.id,
               xmtp_message_id: "public-live-streamed",
               sender_inbox_id: PhaseDApiSupport.deterministic_inbox_id(sender_wallet_address),
               sender_wallet_address: sender_wallet_address,
               sender_label: "Streamed Sender",
               sender_type: :human,
               body: "streamed mirrored xmtp message",
               sent_at: DateTime.utc_now(),
               raw_payload: %{"kind" => "message"},
               moderation_state: "visible"
             })

    assert render(view) =~ "streamed mirrored xmtp message"
    assert has_element?(view, "#chat-human-room-message-public-live-streamed")
  end
end
