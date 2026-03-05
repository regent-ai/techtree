defmodule TechTreeWeb.InternalXmtpControllerTest do
  use TechTreeWeb.ConnCase, async: false

  alias TechTree.Repo
  alias TechTree.XMTPMirror.XmtpMembershipCommand

  setup do
    original_secret = Application.get_env(:tech_tree, :internal_shared_secret, "")
    Application.put_env(:tech_tree, :internal_shared_secret, "test-internal-secret")

    on_exit(fn ->
      Application.put_env(:tech_tree, :internal_shared_secret, original_secret)
    end)

    :ok
  end

  test "requires internal shared secret", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/internal/xmtp/rooms/public-trollbox")

    assert %{"error" => %{"code" => "internal_auth_required"}} = json_response(conn, 401)
  end

  test "denies request when internal shared secret config is invalid", %{conn: conn} do
    Application.put_env(:tech_tree, :internal_shared_secret, 12345)

    on_exit(fn ->
      Application.put_env(:tech_tree, :internal_shared_secret, "test-internal-secret")
    end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/internal/xmtp/rooms/public-trollbox")

    assert %{"error" => %{"code" => "internal_auth_required"}} = json_response(conn, 401)
  end

  test "room and message upsert flow works with secret", %{conn: conn} do
    authed_conn = with_secret(conn)

    room_conn =
      post(authed_conn, "/api/internal/xmtp/rooms/upsert", %{
        "room_key" => "public-trollbox",
        "xmtp_group_id" => "xmtp-public-trollbox",
        "name" => "Public Trollbox",
        "status" => "active"
      })

    assert %{
             "data" => %{
               "room_key" => "public-trollbox",
               "xmtp_group_id" => "xmtp-public-trollbox",
               "name" => "Public Trollbox",
               "status" => "active"
             }
           } = json_response(room_conn, 200)

    get_room_conn = get(authed_conn, "/api/internal/xmtp/rooms/public-trollbox")
    assert %{"data" => %{"room_key" => "public-trollbox"}} = json_response(get_room_conn, 200)

    message_conn =
      post(authed_conn, "/api/internal/xmtp/messages/upsert", %{
        "room_key" => "public-trollbox",
        "xmtp_message_id" => "msg-1",
        "sender_inbox_id" => "inbox-1",
        "sender_wallet_address" => "0xsender",
        "sender_label" => "sender",
        "sender_type" => "human",
        "body" => "hello",
        "sent_at" => DateTime.utc_now(),
        "raw_payload" => %{"kind" => "message"},
        "moderation_state" => "visible"
      })

    assert %{"data" => %{"id" => _id}} = json_response(message_conn, 200)
  end

  test "lease, complete, and fail command flow", %{conn: conn} do
    authed_conn = with_secret(conn)

    {:ok, room_conn} =
      upsert_room_and_seed_command(authed_conn, %{
        "op" => "add_member",
        "xmtp_inbox_id" => "inbox-lease"
      })

    room_id = room_conn["id"]

    lease_conn =
      post(authed_conn, "/api/internal/xmtp/commands/lease", %{
        "room_key" => "public-trollbox"
      })

    assert %{
             "data" => %{
               "id" => leased_id,
               "op" => "add_member",
               "xmtp_inbox_id" => "inbox-lease"
             }
           } = json_response(lease_conn, 200)

    complete_conn = post(authed_conn, "/api/internal/xmtp/commands/#{leased_id}/complete", %{})
    assert %{"ok" => true} = json_response(complete_conn, 200)

    completed = Repo.get!(XmtpMembershipCommand, leased_id)
    assert completed.status == "done"
    assert completed.room_id == room_id

    {:ok, _room} =
      upsert_room_and_seed_command(authed_conn, %{
        "op" => "remove_member",
        "xmtp_inbox_id" => "inbox-fail"
      })

    lease_conn2 =
      post(authed_conn, "/api/internal/xmtp/commands/lease", %{
        "room_key" => "public-trollbox"
      })

    assert %{"data" => %{"id" => leased_id2}} = json_response(lease_conn2, 200)

    fail_conn =
      post(authed_conn, "/api/internal/xmtp/commands/#{leased_id2}/fail", %{
        "error" => "simulated failure"
      })

    assert %{"ok" => true} = json_response(fail_conn, 200)

    failed = Repo.get!(XmtpMembershipCommand, leased_id2)
    assert failed.status == "failed"
    assert failed.last_error == "simulated failure"
  end

  test "lease requires room_key", %{conn: conn} do
    conn =
      conn
      |> with_secret()
      |> post("/api/internal/xmtp/commands/lease", %{})

    assert %{"error" => %{"code" => "room_key_required"}} = json_response(conn, 422)
  end

  test "complete and fail return command_not_found for missing command ids", %{conn: conn} do
    authed_conn = with_secret(conn)

    complete_conn = post(authed_conn, "/api/internal/xmtp/commands/999999/complete", %{})
    assert %{"error" => %{"code" => "command_not_found"}} = json_response(complete_conn, 404)

    fail_conn =
      post(authed_conn, "/api/internal/xmtp/commands/999999/fail", %{
        "error" => "ignored"
      })

    assert %{"error" => %{"code" => "command_not_found"}} = json_response(fail_conn, 404)
  end

  test "fail command defaults blank errors to membership_command_failed", %{conn: conn} do
    authed_conn = with_secret(conn)

    {:ok, _room} =
      upsert_room_and_seed_command(authed_conn, %{
        "op" => "remove_member",
        "xmtp_inbox_id" => "inbox-default-error"
      })

    lease_conn =
      post(authed_conn, "/api/internal/xmtp/commands/lease", %{
        "room_key" => "public-trollbox"
      })

    assert %{"data" => %{"id" => leased_id}} = json_response(lease_conn, 200)

    fail_conn =
      post(authed_conn, "/api/internal/xmtp/commands/#{leased_id}/fail", %{
        "error" => ""
      })

    assert %{"ok" => true} = json_response(fail_conn, 200)

    failed = Repo.get!(XmtpMembershipCommand, leased_id)
    assert failed.last_error == "membership_command_failed"
  end

  defp with_secret(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-tech-tree-secret", "test-internal-secret")
  end

  defp upsert_room_and_seed_command(conn, command_attrs) do
    room_conn =
      post(conn, "/api/internal/xmtp/rooms/upsert", %{
        "room_key" => "public-trollbox",
        "xmtp_group_id" => "xmtp-public-trollbox",
        "name" => "Public Trollbox",
        "status" => "active"
      })

    %{"data" => room_data} = json_response(room_conn, 200)

    command_changeset =
      XmtpMembershipCommand.enqueue_changeset(%XmtpMembershipCommand{}, %{
        room_id: room_data["id"],
        op: command_attrs["op"],
        xmtp_inbox_id: command_attrs["xmtp_inbox_id"]
      })

    {:ok, _command} = Repo.insert(command_changeset)
    {:ok, room_data}
  end
end
