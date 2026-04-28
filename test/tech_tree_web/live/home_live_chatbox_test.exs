defmodule TechTreeWeb.HomeLiveChatboxTest do
  use TechTreeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TechTree.Repo
  alias TechTree.Xmtp
  alias Elixir.Xmtp.MessageLog
  alias Elixir.Xmtp.Room

  @test_agent_private_key "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

  setup do
    configure_xmtp_room!()
    :ok
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

  test "homepage chatbox panels render shared public room messages by sender kind", %{conn: conn} do
    room = bootstrap_public_room!()

    human_message = insert_room_message!(room, "human", "human shared panel message")
    agent_message = insert_room_message!(room, "agent", "agent shared panel message")

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

  defp configure_xmtp_room! do
    original = Application.get_env(:tech_tree, TechTree.Xmtp, [])
    rooms = Keyword.fetch!(original, :rooms)

    configured_rooms =
      Enum.map(rooms, fn
        %{key: "public-chatbox"} = room -> %{room | agent_private_key: @test_agent_private_key}
        room -> room
      end)

    Application.put_env(
      :tech_tree,
      TechTree.Xmtp,
      Keyword.put(original, :rooms, configured_rooms)
    )

    on_exit(fn ->
      Xmtp.reset_for_test!("public-chatbox")
      Application.put_env(:tech_tree, TechTree.Xmtp, original)
    end)
  end

  defp bootstrap_public_room! do
    {:ok, _info} = Xmtp.bootstrap_room!(room_key: "public-chatbox", reuse: true)
    Repo.get_by!(Room, room_key: "public-chatbox")
  end

  defp insert_room_message!(%Room{} = room, sender_kind, body) do
    unique = System.unique_integer([:positive])

    %MessageLog{}
    |> MessageLog.changeset(%{
      room_id: room.id,
      xmtp_message_id: "homepage-room-message-#{sender_kind}-#{unique}",
      conversation_id: room.conversation_id,
      sender_inbox_id: "inbox-#{sender_kind}-#{unique}",
      sender_wallet: "0x#{String.duplicate(Integer.to_string(rem(unique, 10)), 40)}",
      sender_kind: sender_kind,
      sender_label: "#{sender_kind} #{unique}",
      body: body,
      sent_at: DateTime.utc_now(),
      website_visibility_state: "visible",
      message_snapshot: %{"content_type_id" => "text"}
    })
    |> Repo.insert!()
  end
end
