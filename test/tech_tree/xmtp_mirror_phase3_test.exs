defmodule TechTree.XMTPMirrorPhase3Test do
  use TechTree.DataCase, async: false

  alias TechTree.Repo
  alias TechTree.XMTPMirror
  alias TechTree.XMTPMirror.{XmtpMembershipCommand, XmtpMessage}

  test "upsert_message is idempotent for repeated xmtp_message_id" do
    {:ok, room} =
      XMTPMirror.upsert_room(%{
        room_key: "public-trollbox",
        xmtp_group_id: "xmtp-public-trollbox",
        name: "Public Trollbox",
        status: "active"
      })

    attrs = %{
      room_id: room.id,
      xmtp_message_id: "msg-1",
      sender_inbox_id: "inbox-1",
      sender_wallet_address: "0xsender",
      sender_label: "sender",
      sender_type: :human,
      body: "hello world",
      sent_at: DateTime.utc_now(),
      raw_payload: %{"kind" => "message"},
      moderation_state: "visible"
    }

    {:ok, first} = XMTPMirror.upsert_message(attrs)
    {:ok, second} = XMTPMirror.upsert_message(attrs)

    assert first.id == second.id

    count =
      XmtpMessage
      |> where([m], m.xmtp_message_id == "msg-1")
      |> Repo.aggregate(:count, :id)

    assert count == 1
  end

  test "leasing and processing command path is idempotent for one pending command" do
    {:ok, room} =
      XMTPMirror.upsert_room(%{
        room_key: "lease-room",
        xmtp_group_id: "xmtp-lease-room",
        name: "Lease Room",
        status: "active"
      })

    command =
      %XmtpMembershipCommand{}
      |> XmtpMembershipCommand.enqueue_changeset(%{
        room_id: room.id,
        op: "add_member",
        xmtp_inbox_id: "inbox-lease"
      })
      |> Repo.insert!()

    leased = XMTPMirror.lease_next_command(room.room_key)
    assert leased.id == command.id
    assert leased.status == "processing"
    assert leased.attempt_count == 1

    assert XMTPMirror.lease_next_command(room.room_key) == nil

    assert :ok = XMTPMirror.complete_command(leased.id)
    completed = Repo.get!(XmtpMembershipCommand, leased.id)
    assert completed.status == "done"
  end

  test "failed command records error and status" do
    {:ok, room} =
      XMTPMirror.upsert_room(%{
        room_key: "fail-room",
        xmtp_group_id: "xmtp-fail-room",
        name: "Fail Room",
        status: "active"
      })

    command =
      %XmtpMembershipCommand{}
      |> XmtpMembershipCommand.enqueue_changeset(%{
        room_id: room.id,
        op: "remove_member",
        xmtp_inbox_id: "inbox-fail"
      })
      |> Repo.insert!()

    leased = XMTPMirror.lease_next_command(room.room_key)
    assert leased.id == command.id

    assert :ok = XMTPMirror.fail_command(leased.id, "membership op failed")

    failed = Repo.get!(XmtpMembershipCommand, leased.id)
    assert failed.status == "failed"
    assert failed.last_error == "membership op failed"
  end
end
