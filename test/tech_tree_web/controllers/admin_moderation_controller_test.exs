defmodule TechTreeWeb.AdminModerationControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import Ecto.Query
  import TechTree.PhaseDApiSupport

  alias TechTree.Moderation.ModerationAction
  alias TechTree.Repo
  alias TechTree.XMTPMirror.XmtpMembershipCommand

  setup do
    privy = setup_privy_config!()

    on_exit(fn ->
      privy.restore.()
    end)

    {:ok, privy: privy}
  end

  test "requires admin role", %{conn: conn, privy: privy} do
    user = create_human!("moderation-user", role: "user")

    response =
      conn
      |> with_privy_bearer(user.privy_user_id, privy.app_id, privy.private_pem)
      |> post("/v1/admin/chatbox/members/1/add", %{})
      |> json_response(403)

    assert %{"error" => %{"code" => "admin_required"}} = response
  end

  test "returns validation errors for invalid and missing human ids", %{conn: conn, privy: privy} do
    admin = create_human!("moderation-admin-validation", role: "admin")

    invalid_response =
      conn
      |> with_privy_bearer(admin.privy_user_id, privy.app_id, privy.private_pem)
      |> post("/v1/admin/chatbox/members/not-an-id/add", %{})
      |> json_response(422)

    assert %{"error" => %{"code" => "invalid_human_id"}} = invalid_response

    missing_response =
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(admin.privy_user_id, privy.app_id, privy.private_pem)
      |> post("/v1/admin/chatbox/members/99999999/add", %{})
      |> json_response(404)

    assert %{"error" => %{"code" => "human_not_found"}} = missing_response
  end

  test "admin chatbox member endpoints enqueue room actions and log them", %{privy: privy} do
    admin = create_human!("moderation-room-admin", role: "admin")
    target_human = create_human!("moderation-room-human", role: "user")
    _room = create_canonical_room!()

    authed_conn = fn ->
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(admin.privy_user_id, privy.app_id, privy.private_pem)
    end

    assert %{"ok" => true, "data" => %{"status" => "enqueued"}} =
             authed_conn.()
             |> post("/v1/admin/chatbox/members/#{target_human.id}/add", %{"reason" => "room-add"})
             |> json_response(200)

    assert Repo.get_by!(XmtpMembershipCommand,
             human_user_id: target_human.id,
             op: "add_member",
             status: "pending"
           )

    assert %{"ok" => true, "data" => %{"status" => "enqueued"}} =
             authed_conn.()
             |> post("/v1/admin/chatbox/members/#{target_human.id}/remove", %{
               "reason" => "room-remove"
             })
             |> json_response(200)

    assert Repo.get_by!(XmtpMembershipCommand,
             human_user_id: target_human.id,
             op: "remove_member",
             status: "pending"
           )

    assert Repo.aggregate(
             from(a in ModerationAction,
               where:
                 a.actor_ref == ^admin.id and a.target_ref == ^target_human.id and
                   a.action in ["add_chatbox_member", "remove_chatbox_member"]
             ),
             :count,
             :id
           ) == 2
  end

  test "admin chatbox member endpoints report no-op states without logging them again", %{
    privy: privy
  } do
    admin = create_human!("moderation-room-admin-status", role: "admin")
    target_human = create_human!("moderation-room-human-status", role: "user")
    room = create_canonical_room!()

    authed_conn = fn ->
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(admin.privy_user_id, privy.app_id, privy.private_pem)
    end

    assert %{"ok" => true, "data" => %{"status" => "enqueued"}} =
             authed_conn.()
             |> post("/v1/admin/chatbox/members/#{target_human.id}/add", %{"reason" => "room-add"})
             |> json_response(200)

    assert %{"ok" => true, "data" => %{"status" => "already_pending_join"}} =
             authed_conn.()
             |> post("/v1/admin/chatbox/members/#{target_human.id}/add", %{"reason" => "room-add"})
             |> json_response(200)

    add_command =
      Repo.get_by!(XmtpMembershipCommand,
        room_id: room.id,
        human_user_id: target_human.id,
        op: "add_member",
        status: "pending"
      )

    add_command
    |> Ecto.Changeset.change(status: "done")
    |> Repo.update!()

    assert %{"ok" => true, "data" => %{"status" => "already_joined"}} =
             authed_conn.()
             |> post("/v1/admin/chatbox/members/#{target_human.id}/add", %{"reason" => "room-add"})
             |> json_response(200)

    assert %{"ok" => true, "data" => %{"status" => "enqueued"}} =
             authed_conn.()
             |> post("/v1/admin/chatbox/members/#{target_human.id}/remove", %{
               "reason" => "room-remove"
             })
             |> json_response(200)

    assert %{"ok" => true, "data" => %{"status" => "already_pending_removal"}} =
             authed_conn.()
             |> post("/v1/admin/chatbox/members/#{target_human.id}/remove", %{
               "reason" => "room-remove"
             })
             |> json_response(200)

    assert Repo.aggregate(
             from(a in ModerationAction,
               where:
                 a.actor_ref == ^admin.id and a.target_ref == ^target_human.id and
                   a.action in ["add_chatbox_member", "remove_chatbox_member"]
             ),
             :count,
             :id
           ) == 2
  end

  test "admin chatbox add rejects humans who have not completed room setup", %{privy: privy} do
    admin = create_human!("moderation-room-admin-missing", role: "admin")

    {:ok, target_human} =
      TechTree.Accounts.upsert_human_by_privy_id(
        "moderation-room-missing-#{System.unique_integer([:positive])}",
        %{
          "display_name" => "Missing Room Setup",
          "wallet_address" => random_eth_address()
        }
      )

    _room = create_canonical_room!()

    assert %{"error" => %{"code" => "chat_identity_required"}} =
             Phoenix.ConnTest.build_conn()
             |> with_privy_bearer(admin.privy_user_id, privy.app_id, privy.private_pem)
             |> post("/v1/admin/chatbox/members/#{target_human.id}/add", %{})
             |> json_response(422)
  end
end
