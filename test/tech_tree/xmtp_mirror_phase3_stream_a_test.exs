defmodule TechTree.XMTPMirrorPhase3StreamATest do
  use TechTree.DataCase, async: false

  alias TechTree.Accounts
  alias TechTree.Repo
  alias TechTree.XMTPMirror
  alias TechTree.XMTPMirror.{XmtpMembershipCommand, XmtpMessage, XmtpRoom}

  @canonical_room_key "public-trollbox"

  test "request_join enqueues add_member idempotently and does not double-enqueue while processing" do
    room = create_canonical_room!()
    human = create_human!("join")

    assert {:ok, %{status: "pending", human_id: human_id}} = XMTPMirror.request_join(human)
    assert human_id == human.id
    assert command_count(room.id, human.id, "add_member") == 1

    assert {:ok, %{status: "pending", human_id: ^human_id}} = XMTPMirror.request_join(human)
    assert command_count(room.id, human.id, "add_member") == 1

    leased = XMTPMirror.lease_next_command(@canonical_room_key)
    assert leased.op == "add_member"
    assert leased.status == "processing"

    assert {:ok, %{status: "pending", human_id: ^human_id}} = XMTPMirror.request_join(human)
    assert command_count(room.id, human.id, "add_member") == 1
  end

  test "request_join is a no-op when membership is already joined" do
    room = create_canonical_room!()
    human = create_human!("joined")

    done_add = insert_membership_command!(room, human, "add_member", "done")

    assert {:ok, %{status: "joined", human_id: human_id}} = XMTPMirror.request_join(human)
    assert human_id == human.id
    assert Repo.aggregate(XmtpMembershipCommand, :count, :id) == 1
    assert Repo.get!(XmtpMembershipCommand, done_add.id).status == "done"
  end

  test "membership_for reflects room presence and latest command state" do
    human = create_human!("membership")

    assert %{
             human_id: human_id,
             room_key: @canonical_room_key,
             room_present: false,
             state: "room_unavailable"
           } = XMTPMirror.membership_for(human)

    assert human_id == human.id

    room = create_canonical_room!()

    assert %{room_present: true, state: "not_joined"} = XMTPMirror.membership_for(human)

    add_pending = insert_membership_command!(room, human, "add_member", "pending")
    assert %{state: "join_pending"} = XMTPMirror.membership_for(human)

    assert :ok = XMTPMirror.complete_command(add_pending.id)
    assert %{state: "joined"} = XMTPMirror.membership_for(human)

    remove_pending = insert_membership_command!(room, human, "remove_member", "pending")
    assert %{state: "leave_pending"} = XMTPMirror.membership_for(human)

    assert :ok = XMTPMirror.fail_command(remove_pending.id, "membership op failed")
    assert %{state: "leave_failed"} = XMTPMirror.membership_for(human)

    remove_done = insert_membership_command!(room, human, "remove_member", "pending")
    assert :ok = XMTPMirror.complete_command(remove_done.id)
    assert %{state: "not_joined"} = XMTPMirror.membership_for(human)
  end

  test "add_human_to_canonical_room and remove_human_from_canonical_room enqueue canonical ops idempotently" do
    room = create_canonical_room!()
    human = create_human!("admin")

    assert :ok = XMTPMirror.add_human_to_canonical_room(human.id)
    assert command_count(room.id, human.id, "add_member") == 1

    assert :ok = XMTPMirror.add_human_to_canonical_room(human.id)
    assert command_count(room.id, human.id, "add_member") == 1

    _leased = XMTPMirror.lease_next_command(@canonical_room_key)
    assert :ok = XMTPMirror.add_human_to_canonical_room(human.id)
    assert command_count(room.id, human.id, "add_member") == 1

    assert :ok = XMTPMirror.complete_command(latest_command_id!(room.id, human.id, "add_member"))
    assert :ok = XMTPMirror.remove_human_from_canonical_room(human.id)
    assert command_count(room.id, human.id, "remove_member") == 1

    assert :ok = XMTPMirror.remove_human_from_canonical_room(human.id)
    assert command_count(room.id, human.id, "remove_member") == 1
  end

  test "list_public_messages excludes hidden and is deterministic for equal sent_at values" do
    canonical_room = create_canonical_room!()
    other_room = create_room!("secondary-room")

    tie_timestamp = ~U[2026-03-01 12:00:00.000000Z]
    latest_timestamp = ~U[2026-03-01 12:00:01.000000Z]

    tie_first = insert_message!(canonical_room, "tie-first", tie_timestamp, "visible")
    tie_second = insert_message!(canonical_room, "tie-second", tie_timestamp, "visible")
    newest = insert_message!(canonical_room, "newest", latest_timestamp, "visible")
    _hidden = insert_message!(canonical_room, "hidden", latest_timestamp, "hidden")
    _other_room = insert_message!(other_room, "other-room", latest_timestamp, "visible")

    messages = XMTPMirror.list_public_messages(%{"limit" => "10"})
    assert Enum.map(messages, & &1.id) == [newest.id, tie_second.id, tie_first.id]
  end

  defp create_canonical_room! do
    create_room!(@canonical_room_key)
  end

  defp create_room!(room_key) do
    %XmtpRoom{}
    |> XmtpRoom.changeset(%{
      room_key: room_key,
      name: "Room #{room_key}",
      status: "active",
      xmtp_group_id: "group-#{room_key}-#{System.unique_integer([:positive])}"
    })
    |> Repo.insert!()
  end

  defp create_human!(label) do
    unique = System.unique_integer([:positive])

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("privy-#{label}-#{unique}", %{
        "wallet_address" => "0x#{label}#{unique}",
        "xmtp_inbox_id" => "inbox-#{label}-#{unique}",
        "display_name" => "human-#{label}-#{unique}"
      })

    human
  end

  defp insert_membership_command!(room, human, op, status) do
    %XmtpMembershipCommand{}
    |> XmtpMembershipCommand.enqueue_changeset(%{
      room_id: room.id,
      human_user_id: human.id,
      op: op,
      xmtp_inbox_id: human.xmtp_inbox_id,
      status: status
    })
    |> Repo.insert!()
  end

  defp insert_message!(room, message_label, sent_at, moderation_state) do
    unique = System.unique_integer([:positive])

    %XmtpMessage{}
    |> XmtpMessage.changeset(%{
      room_id: room.id,
      xmtp_message_id: "msg-#{message_label}-#{unique}",
      sender_inbox_id: "sender-#{unique}",
      sender_wallet_address: "0xsender#{unique}",
      sender_label: "sender-#{unique}",
      sender_type: :human,
      body: "message #{message_label}",
      sent_at: sent_at,
      moderation_state: moderation_state,
      raw_payload: %{"message" => message_label}
    })
    |> Repo.insert!()
  end

  defp command_count(room_id, human_id, op) do
    XmtpMembershipCommand
    |> where([c], c.room_id == ^room_id and c.human_user_id == ^human_id and c.op == ^op)
    |> Repo.aggregate(:count, :id)
  end

  defp latest_command_id!(room_id, human_id, op) do
    XmtpMembershipCommand
    |> where([c], c.room_id == ^room_id and c.human_user_id == ^human_id and c.op == ^op)
    |> order_by([c], desc: c.inserted_at, desc: c.id)
    |> limit(1)
    |> Repo.one!()
    |> Map.fetch!(:id)
  end
end
