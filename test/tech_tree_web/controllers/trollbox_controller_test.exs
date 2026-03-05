defmodule TechTreeWeb.TrollboxControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import TechTree.PhaseDApiSupport

  alias TechTree.Repo
  alias TechTree.Accounts.HumanUser
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

    assert %{"data" => %{"id" => message_id, "body" => "phase-d human post", "sender_type" => "human"}} =
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
