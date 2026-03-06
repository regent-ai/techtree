defmodule TechTreeWeb.TrollboxControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import TechTree.PhaseDApiSupport

  alias TechTree.Repo
  alias TechTree.Accounts.HumanUser
  alias TechTree.XMTPMirror
  alias TechTree.XMTPMirror.XmtpMembershipCommand

  setup do
    Process.put(:tech_tree_disable_rate_limits, true)
    privy = setup_privy_config!()
    room = create_canonical_room!()
    human = create_human!("trollbox-controller", role: "user")

    authed_conn =
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(human.privy_user_id, privy.app_id, privy.private_pem)

    on_exit(fn ->
      Process.delete(:tech_tree_disable_rate_limits)
      privy.restore.()
    end)

    {:ok, conn: authed_conn, human: human, room: room, privy: privy}
  end

  test "POST /v1/trollbox/messages requires joined membership", %{conn: conn} do
    response =
      conn
      |> post("/v1/trollbox/messages", %{"body" => "hello world"})
      |> json_response(403)

    assert %{"error" => %{"code" => "membership_required"}} = response
  end

  test "POST /v1/trollbox/messages persists human message for joined members", %{
    conn: conn,
    human: human,
    room: room
  } do
    mark_human_joined!(room.id, human.id, human.xmtp_inbox_id)

    assert %{
             "data" => %{
               "id" => message_id,
               "body" => "phase-d human post",
               "sender_type" => "human"
             }
           } =
             conn
             |> post("/v1/trollbox/messages", %{
               "body" => "phase-d human post"
             })
             |> json_response(202)

    assert %{"data" => messages} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/trollbox/messages")
             |> json_response(200)

    assert Enum.any?(messages, &(&1["id"] == message_id && &1["body"] == "phase-d human post"))
  end

  test "POST /v1/trollbox/request-join binds xmtp inbox when missing", %{privy: privy} do
    human = create_human!("bind-inbox", role: "user", xmtp_inbox_id: nil)

    conn =
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(human.privy_user_id, privy.app_id, privy.private_pem)

    inbox_id = "inbox-bind-#{System.unique_integer([:positive])}"

    assert %{
             "data" => %{
               "status" => status,
               "human_id" => human_id,
               "room_key" => "public-trollbox",
               "shard_key" => "public-trollbox",
               "xmtp_group_id" => xmtp_group_id
             }
           } =
             conn
             |> post("/v1/trollbox/request-join", %{"xmtp_inbox_id" => inbox_id})
             |> json_response(200)

    assert status in ["pending", "joined"]
    assert human_id == human.id
    assert is_binary(xmtp_group_id)
    assert Repo.get!(HumanUser, human.id).xmtp_inbox_id == inbox_id
  end

  test "POST /v1/trollbox/presence/heartbeat requires joined membership", %{conn: conn} do
    response =
      conn
      |> post("/v1/trollbox/presence/heartbeat", %{})
      |> json_response(403)

    assert %{"error" => %{"code" => "membership_required"}} = response
  end

  test "POST /v1/trollbox/presence/heartbeat returns liveness payload for joined members", %{
    conn: conn,
    human: human,
    room: room
  } do
    mark_human_joined!(room.id, human.id, human.xmtp_inbox_id)

    assert %{
             "data" => %{
               "status" => "alive",
               "room_key" => "public-trollbox",
               "shard_key" => "public-trollbox",
               "ttl_seconds" => ttl_seconds,
               "eviction_enqueued" => eviction_enqueued,
               "observed_at" => observed_at,
               "expires_at" => expires_at
             }
           } =
             conn
             |> post("/v1/trollbox/presence/heartbeat", %{})
             |> json_response(200)

    assert is_integer(ttl_seconds)
    assert is_integer(eviction_enqueued)
    assert {:ok, _observed, _} = DateTime.from_iso8601(observed_at)
    assert {:ok, _expires, _} = DateTime.from_iso8601(expires_at)
  end

  test "POST /v1/trollbox/messages sends to selected shard and list filters by shard", %{
    conn: conn,
    human: human
  } do
    shard = create_shard_room!("public-trollbox-shard-2")
    mark_human_joined!(shard.id, human.id, human.xmtp_inbox_id)

    assert %{
             "data" => %{
               "id" => message_id,
               "room_key" => room_key,
               "shard_key" => shard_key,
               "body" => "shard scoped post"
             }
           } =
             conn
             |> post("/v1/trollbox/messages", %{
               "body" => "shard scoped post",
               "shard_key" => shard.room_key
             })
             |> json_response(202)

    assert room_key == shard.room_key
    assert shard_key == shard.room_key

    assert %{"data" => messages} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/trollbox/messages", %{"shard_key" => shard.room_key})
             |> json_response(200)

    assert Enum.any?(messages, &(&1["id"] == message_id && &1["room_key"] == shard.room_key))
  end

  test "GET /v1/trollbox/membership returns state for selected shard", %{conn: conn, human: human} do
    shard = create_shard_room!("public-trollbox-shard-3")
    mark_human_joined!(shard.id, human.id, human.xmtp_inbox_id)

    assert %{"data" => %{"state" => "joined", "room_key" => room_key}} =
             conn
             |> get("/v1/trollbox/membership", %{"shard_key" => shard.room_key})
             |> json_response(200)

    assert room_key == shard.room_key

    assert %{"data" => %{"state" => "not_joined", "room_key" => "public-trollbox"}} =
             conn
             |> get("/v1/trollbox/membership", %{"shard_key" => "public-trollbox"})
             |> json_response(200)
  end

  test "POST /v1/trollbox/presence/heartbeat honors selected shard membership", %{
    conn: conn,
    human: human
  } do
    shard = create_shard_room!("public-trollbox-shard-4")
    mark_human_joined!(shard.id, human.id, human.xmtp_inbox_id)

    assert %{
             "data" => %{
               "status" => "alive",
               "room_key" => room_key,
               "shard_key" => shard_key
             }
           } =
             conn
             |> post("/v1/trollbox/presence/heartbeat", %{"shard_key" => shard.room_key})
             |> json_response(200)

    assert room_key == shard.room_key
    assert shard_key == shard.room_key
  end

  test "POST /v1/trollbox/messages/:id/reactions updates emoji counts for joined members", %{
    conn: conn,
    human: human,
    room: room
  } do
    mark_human_joined!(room.id, human.id, human.xmtp_inbox_id)

    message_id =
      room
      |> create_visible_message!(%{sender_inbox_id: "sender-react"})
      |> Map.fetch!(:id)

    assert %{"data" => %{"id" => ^message_id, "reactions" => %{"🔥" => 1}}} =
             conn
             |> post("/v1/trollbox/messages/#{message_id}/reactions", %{"emoji" => "🔥"})
             |> json_response(200)

    assert %{"data" => %{"id" => ^message_id, "reactions" => %{}}} =
             conn
             |> post("/v1/trollbox/messages/#{message_id}/reactions", %{
               "emoji" => "🔥",
               "op" => "remove"
             })
             |> json_response(200)
  end

  test "POST /v1/trollbox/messages/:id/reactions requires joined membership", %{
    conn: conn,
    room: room
  } do
    message_id =
      room
      |> create_visible_message!(%{sender_inbox_id: "sender-no-membership"})
      |> Map.fetch!(:id)

    assert %{"error" => %{"code" => "membership_required"}} =
             conn
             |> post("/v1/trollbox/messages/#{message_id}/reactions", %{"emoji" => "🔥"})
             |> json_response(403)
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

  defp create_shard_room!(room_key) do
    unique = System.unique_integer([:positive, :monotonic])

    {:ok, room} =
      XMTPMirror.ensure_room(%{
        room_key: room_key,
        xmtp_group_id: "xmtp-#{room_key}-#{unique}",
        name: "Shard #{unique}",
        status: "active"
      })

    room
  end
end
