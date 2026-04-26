defmodule TechTreeWeb.ChatboxControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import TechTree.PhaseDApiSupport

  alias Phoenix.Socket.Broadcast
  alias TechTree.Chatbox

  setup do
    privy = setup_privy_config!()
    human = create_human!("chatbox-controller", role: "user")
    room = create_canonical_room!()
    _membership = join_public_room!(room, human)

    authed_conn =
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(human.privy_user_id, privy.app_id, privy.private_pem)

    on_exit(fn ->
      privy.restore.()
    end)

    {:ok, conn: authed_conn, human: human, privy: privy, room: room}
  end

  test "GET /v1/chatbox/messages returns canonical messages with pagination", %{human: human} do
    older = create_chatbox_message!(human, %{body: "older-message"})
    newer = create_chatbox_message!(human, %{body: "newer-message"})

    assert %{"data" => [first], "next_cursor" => next_cursor} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/chatbox/messages", %{"limit" => "1", "room" => "webapp"})
             |> json_response(200)

    assert first["id"] == newer.id
    assert next_cursor == newer.id

    assert %{"data" => older_page, "next_cursor" => _next_cursor} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/chatbox/messages", %{
               "before" => next_cursor,
               "limit" => "10",
               "room" => "webapp"
             })
             |> json_response(200)

    assert Enum.any?(older_page, &(&1["id"] == older.id))
  end

  test "GET /v1/chatbox/messages rejects unsupported room filters" do
    assert %{"error" => %{"code" => "invalid_chatbox_room"}} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/chatbox/messages", %{"room" => "agent"})
             |> json_response(422)
  end

  test "GET /v1/chatbox/messages rejects blank room filters" do
    assert %{"error" => %{"code" => "invalid_chatbox_room"}} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/chatbox/messages", %{"room" => "   "})
             |> json_response(422)
  end

  test "POST /v1/chatbox/messages persists and broadcasts human messages", %{conn: conn} do
    Phoenix.PubSub.subscribe(TechTree.PubSub, Chatbox.channel_topic())
    :ok = Chatbox.subscribe()

    assert %{
             "data" => %{
               "id" => message_id,
               "body" => "phase-d human post",
               "author_kind" => "human"
             }
           } =
             conn
             |> post("/v1/chatbox/messages", %{"body" => "phase-d human post"})
             |> json_response(201)

    assert_receive %Broadcast{
      topic: "chatbox:public",
      event: "message.created",
      payload: %{event: "message.created", message: %{id: ^message_id}}
    }

    assert_receive {:chatbox_event,
                    %{
                      event: "message.created",
                      message: %{id: ^message_id, body: "phase-d human post"}
                    }}
  end

  test "POST /v1/chatbox/messages is idempotent per human client_message_id", %{conn: conn} do
    payload = %{"body" => "repeatable", "client_message_id" => "msg-client-1"}
    auth_header = conn |> get_req_header("authorization") |> List.first()

    assert %{"data" => %{"id" => message_id}} =
             conn
             |> post("/v1/chatbox/messages", payload)
             |> json_response(201)

    assert %{"data" => %{"id" => ^message_id}} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> put_req_header("authorization", auth_header)
             |> post("/v1/chatbox/messages", payload)
             |> json_response(200)
  end

  test "POST /v1/chatbox/messages rejects invalid reply targets", %{conn: conn} do
    assert %{"error" => %{"code" => "invalid_reply_to_message"}} =
             conn
             |> post("/v1/chatbox/messages", %{
               "body" => "replying into the void",
               "reply_to_message_id" => 999_999
             })
             |> json_response(422)
  end

  test "POST /v1/chatbox/messages/:id/reactions updates emoji counts", %{
    conn: conn,
    human: human
  } do
    message = create_chatbox_message!(human, %{body: "react-here"})
    message_id = message.id

    assert %{"data" => %{"id" => ^message_id, "reactions" => %{"🔥" => 1}}} =
             conn
             |> post("/v1/chatbox/messages/#{message.id}/reactions", %{"emoji" => "🔥"})
             |> json_response(200)

    assert %{"data" => %{"id" => ^message_id, "reactions" => %{}}} =
             conn
             |> post("/v1/chatbox/messages/#{message.id}/reactions", %{
               "emoji" => "🔥",
               "op" => "remove"
             })
             |> json_response(200)
  end

  test "POST /v1/chatbox/messages/:id/reactions is idempotent per human actor", %{
    conn: conn,
    human: human
  } do
    message = create_chatbox_message!(human, %{body: "react-once"})
    message_id = message.id

    assert %{"data" => %{"id" => ^message_id, "reactions" => %{"🔥" => 1}}} =
             conn
             |> post("/v1/chatbox/messages/#{message.id}/reactions", %{"emoji" => "🔥"})
             |> json_response(200)

    assert %{"data" => %{"id" => ^message_id, "reactions" => %{"🔥" => 1}}} =
             conn
             |> post("/v1/chatbox/messages/#{message.id}/reactions", %{"emoji" => "🔥"})
             |> json_response(200)
  end

  test "POST /v1/chatbox/messages rate limits duplicate bodies for the same human", %{conn: conn} do
    assert %{"data" => %{"body" => "duplicate-body"}} =
             conn
             |> post("/v1/chatbox/messages", %{"body" => "duplicate-body"})
             |> json_response(201)

    assert %{
             "error" => %{
               "code" => "duplicate_message_cooldown",
               "retry_after_ms" => retry_after_ms
             }
           } =
             conn
             |> post("/v1/chatbox/messages", %{"body" => "duplicate-body"})
             |> json_response(429)

    assert is_integer(retry_after_ms)
    assert retry_after_ms > 0
  end

  test "POST /v1/chatbox/messages rate limits bursts for the same human", %{conn: conn} do
    Enum.each(1..6, fn index ->
      body = "burst-#{index}"

      assert %{"data" => %{"body" => ^body}} =
               conn
               |> post("/v1/chatbox/messages", %{"body" => body})
               |> json_response(201)
    end)

    assert %{"error" => %{"code" => "message_rate_limited", "retry_after_ms" => retry_after_ms}} =
             conn
             |> post("/v1/chatbox/messages", %{"body" => "burst-7"})
             |> json_response(429)

    assert is_integer(retry_after_ms)
    assert retry_after_ms > 0
  end

  test "POST /v1/chatbox/messages rejects banned humans", %{privy: privy} do
    human = create_human!("chatbox-banned", role: "banned")

    conn =
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(human.privy_user_id, privy.app_id, privy.private_pem)

    assert %{"error" => %{"code" => "human_banned"}} =
             conn
             |> post("/v1/chatbox/messages", %{"body" => "banned post"})
             |> json_response(403)
  end

  test "POST /v1/chatbox/messages rejects humans without a stored room identity", %{privy: privy} do
    {:ok, human} =
      TechTree.Accounts.upsert_human_by_privy_id("privy-chatbox-no-room", %{
        "display_name" => "No Room User",
        "wallet_address" => "0x1234567890123456789012345678901234567890"
      })

    conn =
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(human.privy_user_id, privy.app_id, privy.private_pem)

    assert %{"error" => %{"code" => "chat_identity_required"}} =
             conn
             |> post("/v1/chatbox/messages", %{"body" => "should work"})
             |> json_response(422)
  end

  test "POST /v1/chatbox/messages requires a joined public room", %{privy: privy} do
    human = create_human!("chatbox-not-joined")

    conn =
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(human.privy_user_id, privy.app_id, privy.private_pem)

    assert %{"error" => %{"code" => "chat_membership_required"}} =
             conn
             |> post("/v1/chatbox/messages", %{"body" => "not joined"})
             |> json_response(422)
  end

  test "POST /v1/chatbox/messages rejects posting while the browser wallet switch is still unfinished",
       %{privy: privy} do
    ready_wallet = "0x2234567890123456789012345678901234567890"
    pending_wallet = "0x3234567890123456789012345678901234567890"

    {:ok, human} =
      TechTree.Accounts.upsert_human_by_privy_id("privy-chatbox-pending-wallet", %{
        "display_name" => "Pending Wallet User",
        "wallet_address" => ready_wallet,
        "xmtp_inbox_id" => deterministic_inbox_id(ready_wallet)
      })

    conn =
      Phoenix.ConnTest.build_conn()
      |> init_test_session(%{
        privy_user_id: human.privy_user_id,
        privy_pending_wallet_address: pending_wallet
      })
      |> with_privy_bearer(human.privy_user_id, privy.app_id, privy.private_pem)

    assert %{"error" => %{"code" => "chat_identity_required"}} =
             conn
             |> post("/v1/chatbox/messages", %{"body" => "should stay blocked"})
             |> json_response(422)
  end

  test "POST /v1/chatbox/messages/:id/reactions rejects humans without a stored room identity", %{
    privy: privy,
    human: human
  } do
    message = create_chatbox_message!(human, %{body: "react-target-no-room"})

    {:ok, missing_room_human} =
      TechTree.Accounts.upsert_human_by_privy_id("privy-chatbox-react-no-room", %{
        "display_name" => "No Room User",
        "wallet_address" => "0x1234567890123456789012345678901234567890"
      })

    conn =
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(missing_room_human.privy_user_id, privy.app_id, privy.private_pem)

    assert %{"error" => %{"code" => "chat_identity_required"}} =
             conn
             |> post("/v1/chatbox/messages/#{message.id}/reactions", %{"emoji" => "🔥"})
             |> json_response(422)
  end

  test "POST /v1/chatbox/messages rejects humans with stale saved room identities", %{
    privy: privy
  } do
    wallet_address = "0x2234567890123456789012345678901234567890"

    {:ok, human} =
      TechTree.Accounts.upsert_human_by_privy_id("privy-chatbox-stale-room", %{
        "display_name" => "Stale Room User",
        "wallet_address" => wallet_address,
        "xmtp_inbox_id" => "stale-inbox-id"
      })

    conn =
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(human.privy_user_id, privy.app_id, privy.private_pem)

    assert %{"error" => %{"code" => "chat_identity_required"}} =
             conn
             |> post("/v1/chatbox/messages", %{"body" => "should work"})
             |> json_response(422)
  end

  test "POST /v1/chatbox/messages/:id/reactions rejects humans with stale saved room identities",
       %{
         privy: privy,
         human: human
       } do
    message = create_chatbox_message!(human, %{body: "react-target-stale-room"})
    wallet_address = "0x3234567890123456789012345678901234567890"

    {:ok, stale_room_human} =
      TechTree.Accounts.upsert_human_by_privy_id("privy-chatbox-react-stale-room", %{
        "display_name" => "Stale Room User",
        "wallet_address" => wallet_address,
        "xmtp_inbox_id" => "stale-inbox-id"
      })

    conn =
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(stale_room_human.privy_user_id, privy.app_id, privy.private_pem)

    assert %{"error" => %{"code" => "chat_identity_required"}} =
             conn
             |> post("/v1/chatbox/messages/#{message.id}/reactions", %{"emoji" => "🔥"})
             |> json_response(422)
  end
end
