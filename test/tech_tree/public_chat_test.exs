defmodule TechTree.PublicChatTest do
  use TechTree.DataCase, async: false

  import TechTree.PhaseDApiSupport,
    only: [
      create_canonical_room!: 0,
      create_human!: 1,
      create_human!: 2,
      create_visible_message!: 2,
      join_public_room!: 2
    ]

  alias TechTree.{PublicChat, PublicEvents}
  alias TechTree.Repo
  alias TechTree.XMTPMirror
  alias TechTree.XMTPMirror.XmtpMembershipCommand

  setup do
    %{room: create_canonical_room!(), human: create_human!("public-chat")}
  end

  test "anonymous visitors can read the mirrored public room", %{room: room} do
    message =
      create_visible_message!(room, %{
        sender_type: :human,
        sender_label: "reader",
        body: "visible to everyone"
      })

    panel = PublicChat.room_panel(nil)

    refute panel.joined?
    refute panel.can_join?
    refute panel.can_send?
    assert Enum.map(panel.messages, & &1.id) == [message.id]
  end

  test "posting requires mirror membership and broadcasts saved messages", %{
    room: room,
    human: human
  } do
    assert {:error, :xmtp_membership_required} = PublicChat.send_message(human, "before join")

    join_public_room!(room, human)
    :ok = PublicEvents.subscribe()

    assert {:ok, panel} = PublicChat.send_message(human, "after join")
    assert panel.joined?
    assert panel.can_send?

    assert_receive {:public_site_event,
                    %{
                      event: :xmtp_room_message,
                      room_key: "public-chatbox",
                      message: %{body: "after join"}
                    }}
  end

  test "completed join commands refresh the public room", %{room: room, human: human} do
    assert {:ok, _panel} = PublicChat.request_join(human)
    command = Repo.get_by!(XmtpMembershipCommand, room_id: room.id, human_user_id: human.id)

    :ok = PublicEvents.subscribe()

    assert :ok = XMTPMirror.resolve_command(command.id, %{"status" => "done"})

    assert_receive {:public_site_event,
                    %{
                      event: :xmtp_room_membership,
                      room_key: "public-chatbox"
                    }}

    assert PublicChat.room_panel(human).membership_state == :joined
  end

  test "one human cannot join two public rooms at the same time", %{room: room, human: human} do
    join_public_room!(room, human)
    suffix = System.unique_integer([:positive])

    {:ok, shard_room} =
      XMTPMirror.ensure_room(%{
        "room_key" => "public-chatbox-shard-#{suffix}",
        "xmtp_group_id" => "xmtp-public-chatbox-shard-#{suffix}",
        "name" => "Public Chatbox ##{suffix}",
        "status" => "active"
      })

    assert {:error, :already_in_room} =
             XMTPMirror.request_join(human, %{"room_key" => shard_room.room_key})
  end

  test "banned human messages stay out of public reads", %{room: room} do
    banned = create_human!("banned-reader", role: "banned")

    create_visible_message!(room, %{
      sender_wallet_address: banned.wallet_address,
      sender_inbox_id: banned.xmtp_inbox_id,
      sender_type: :human,
      body: "do not relay"
    })

    assert PublicChat.room_panel(nil).messages == []
  end
end
