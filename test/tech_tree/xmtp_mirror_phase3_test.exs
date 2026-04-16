defmodule TechTree.XMTPMirrorPhase3Test do
  use TechTree.DataCase, async: false

  alias TechTree.Accounts
  alias TechTree.Repo
  alias TechTree.XMTPMirror
  alias TechTree.XMTPMirror.{XmtpMembershipCommand, XmtpMessage, XmtpPresence}

  test "ingest_message is idempotent for repeated xmtp_message_id" do
    {:ok, room} =
      XMTPMirror.ensure_room(%{
        room_key: "public-chatbox",
        xmtp_group_id: "xmtp-public-chatbox",
        name: "Public Chatbox",
        status: "active"
      })

    sender_wallet_address = TechTree.PhaseDApiSupport.random_eth_address()

    attrs = %{
      room_id: room.id,
      xmtp_message_id: "msg-1",
      sender_inbox_id: TechTree.PhaseDApiSupport.deterministic_inbox_id(sender_wallet_address),
      sender_wallet_address: sender_wallet_address,
      sender_label: "sender",
      sender_type: :human,
      body: "hello world",
      sent_at: DateTime.utc_now(),
      raw_payload: %{"kind" => "message"},
      moderation_state: "visible"
    }

    {:ok, first} = XMTPMirror.ingest_message(attrs)
    {:ok, second} = XMTPMirror.ingest_message(attrs)

    assert first.id == second.id

    count =
      XmtpMessage
      |> where([m], m.xmtp_message_id == "msg-1")
      |> Repo.aggregate(:count, :id)

    assert count == 1
  end

  test "leasing and processing command path is idempotent for one pending command" do
    {:ok, room} =
      XMTPMirror.ensure_room(%{
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

    assert :ok = XMTPMirror.resolve_command(leased.id, %{status: "done"})
    completed = Repo.get!(XmtpMembershipCommand, leased.id)
    assert completed.status == "done"
  end

  test "resolve_command with failed status records error and status" do
    {:ok, room} =
      XMTPMirror.ensure_room(%{
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

    assert :ok =
             XMTPMirror.resolve_command(leased.id, %{
               status: "failed",
               error: "membership op failed"
             })

    failed = Repo.get!(XmtpMembershipCommand, leased.id)
    assert failed.status == "failed"
    assert failed.last_error == "membership op failed"
  end

  test "request_join and create_human_message are shard-aware" do
    {:ok, _canonical} =
      XMTPMirror.ensure_room(%{
        room_key: "public-chatbox",
        xmtp_group_id: "xmtp-public-chatbox-shard-aware",
        name: "Public Chatbox",
        status: "active"
      })

    {:ok, shard_room} =
      XMTPMirror.ensure_room(%{
        room_key: "public-chatbox-shard-2",
        xmtp_group_id: "xmtp-public-chatbox-shard-2",
        name: "Public Chatbox #2",
        status: "active"
      })

    human = create_human!("shard-aware")

    assert {:ok, %{room_key: room_key}} =
             XMTPMirror.request_join(human, %{"shard_key" => shard_room.room_key})

    assert room_key == shard_room.room_key

    mark_human_joined!(shard_room.id, human.id, human.xmtp_inbox_id)

    assert {:ok, message} =
             XMTPMirror.create_human_message(human, %{
               "body" => "hello shard room",
               "shard_key" => shard_room.room_key
             })

    assert message.room_id == shard_room.id

    assert Enum.any?(
             XMTPMirror.list_public_messages(%{"shard_key" => shard_room.room_key}),
             &(&1.id == message.id)
           )
  end

  test "heartbeat_presence enqueues stale leave commands for expired presences" do
    {:ok, room} =
      XMTPMirror.ensure_room(%{
        room_key: "presence-room",
        xmtp_group_id: "xmtp-presence-room",
        name: "Presence Room",
        status: "active",
        presence_ttl_seconds: 120
      })

    active_human = create_human!("presence-active")
    stale_human = create_human!("presence-stale")

    mark_human_joined!(room.id, active_human.id, active_human.xmtp_inbox_id)
    mark_human_joined!(room.id, stale_human.id, stale_human.xmtp_inbox_id)

    observed_at = DateTime.utc_now() |> DateTime.add(-240, :second)
    expires_at = DateTime.add(observed_at, 120, :second)

    %XmtpPresence{}
    |> XmtpPresence.changeset(%{
      room_id: room.id,
      human_user_id: stale_human.id,
      xmtp_inbox_id: stale_human.xmtp_inbox_id,
      last_seen_at: observed_at,
      expires_at: expires_at,
      evicted_at: nil
    })
    |> Repo.insert!()

    assert {:ok, %{status: "alive", room_key: room_key, eviction_enqueued: 1}} =
             XMTPMirror.heartbeat_presence(active_human, %{"shard_key" => room.room_key})

    assert room_key == room.room_key

    assert Repo.get_by(XmtpMembershipCommand,
             room_id: room.id,
             human_user_id: stale_human.id,
             xmtp_inbox_id: stale_human.xmtp_inbox_id,
             op: "remove_member",
             status: "pending"
           )
  end

  defp create_human!(prefix) do
    unique = System.unique_integer([:positive, :monotonic])
    wallet_address = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("privy-#{prefix}-#{unique}", %{
        "display_name" => "#{prefix}-#{unique}",
        "wallet_address" => wallet_address,
        "xmtp_inbox_id" => TechTree.PhaseDApiSupport.deterministic_inbox_id(wallet_address),
        "role" => "user"
      })

    human
  end

  defp mark_human_joined!(room_id, human_id, inbox_id) do
    %XmtpMembershipCommand{}
    |> XmtpMembershipCommand.enqueue_changeset(%{
      room_id: room_id,
      human_user_id: human_id,
      op: "add_member",
      xmtp_inbox_id: inbox_id,
      status: "done"
    })
    |> Repo.insert!()
  end
end
