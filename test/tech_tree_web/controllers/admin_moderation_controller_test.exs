defmodule TechTreeWeb.AdminModerationControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import Ecto.Query
  import TechTree.PhaseDApiSupport, except: [create_agent!: 1]

  alias TechTree.Agents
  alias TechTree.Comments.Comment
  alias TechTree.Moderation.ModerationAction
  alias TechTree.Nodes.Node
  alias TechTree.Repo
  alias TechTree.XMTPMirror
  alias TechTree.XMTPMirror.{XmtpMembershipCommand, XmtpMessage}

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
      |> post("/v1/admin/nodes/1/hide", %{})
      |> json_response(403)

    assert %{"error" => %{"code" => "admin_required"}} = response
  end

  test "returns validation errors for invalid and missing node ids", %{conn: conn, privy: privy} do
    admin = create_human!("moderation-admin-validation", role: "admin")

    invalid_response =
      conn
      |> with_privy_bearer(admin.privy_user_id, privy.app_id, privy.private_pem)
      |> post("/v1/admin/nodes/not-an-id/hide", %{})
      |> json_response(422)

    assert %{"error" => %{"code" => "invalid_node_id"}} = invalid_response

    missing_response =
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(admin.privy_user_id, privy.app_id, privy.private_pem)
      |> post("/v1/admin/nodes/99999999/hide", %{})
      |> json_response(404)

    assert %{"error" => %{"code" => "node_not_found"}} = missing_response
  end

  test "moderation endpoints mutate targets and log actions", %{conn: conn, privy: privy} do
    admin = create_human!("moderation-admin", role: "admin")
    creator = create_agent!("moderation-creator")
    target_agent = create_agent!("moderation-target-agent")
    target_human = create_human!("moderation-target-human", role: "user")
    membership_human = create_human!("moderation-membership-human", role: "user")

    node = create_node!(creator)
    comment = create_comment!(node.id, creator.id)
    message = create_message!()

    :ok =
      ensure_canonical_room_exists()

    authed_conn = fn ->
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(admin.privy_user_id, privy.app_id, privy.private_pem)
    end

    assert %{"ok" => true} =
             authed_conn.()
             |> post("/v1/admin/nodes/#{node.id}/hide", %{"reason" => "hide-node"})
             |> json_response(200)

    assert %{"ok" => true} =
             authed_conn.()
             |> post("/v1/admin/comments/#{comment.id}/hide", %{"reason" => "hide-comment"})
             |> json_response(200)

    assert %{"ok" => true} =
             authed_conn.()
             |> post("/v1/admin/trollbox/messages/#{message.id}/hide", %{
               "reason" => "hide-message"
             })
             |> json_response(200)

    assert %{"ok" => true} =
             authed_conn.()
             |> post("/v1/admin/agents/#{target_agent.id}/ban", %{"reason" => "ban-agent"})
             |> json_response(200)

    assert %{"ok" => true} =
             authed_conn.()
             |> post("/v1/admin/humans/#{target_human.id}/ban", %{"reason" => "ban-human"})
             |> json_response(200)

    assert %{"ok" => true} =
             authed_conn.()
             |> post("/v1/admin/trollbox/members/#{membership_human.id}/add", %{})
             |> json_response(200)

    assert %{"ok" => true} =
             authed_conn.()
             |> post("/v1/admin/trollbox/members/#{membership_human.id}/remove", %{})
             |> json_response(200)

    assert Repo.get!(Node, node.id).status == :hidden
    assert Repo.get!(Comment, comment.id).status == :hidden
    assert Repo.get!(XmtpMessage, message.id).moderation_state == "hidden"
    assert Repo.get!(TechTree.Agents.AgentIdentity, target_agent.id).status == "banned"
    assert Repo.get!(TechTree.Accounts.HumanUser, target_human.id).role == "banned"

    assert Repo.aggregate(
             from(a in ModerationAction, where: a.actor_ref == ^admin.id),
             :count,
             :id
           ) >= 5

    assert Repo.exists?(
             from(c in XmtpMembershipCommand,
               where: c.human_user_id == ^membership_human.id and c.op == "add_member"
             )
           )

    assert Repo.exists?(
             from(c in XmtpMembershipCommand,
               where: c.human_user_id == ^membership_human.id and c.op == "remove_member"
             )
           )
  end

  defp create_agent!(prefix) do
    unique = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => "8453",
      "registry_address" => "0x#{prefix}-registry-#{unique}",
      "token_id" => Integer.to_string(unique),
      "wallet_address" => "0x#{prefix}-wallet-#{unique}",
      "label" => "#{prefix}-#{unique}"
    })
  end

  defp create_node!(creator) do
    unique = System.unique_integer([:positive])

    %Node{}
    |> Ecto.Changeset.change(%{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "moderation-node-#{unique}",
      status: :anchored,
      notebook_source: "print('node')",
      publish_idempotency_key: "moderation-node:#{unique}",
      creator_agent_id: creator.id
    })
    |> Repo.insert!()
  end

  defp create_comment!(node_id, author_agent_id) do
    %Comment{}
    |> Ecto.Changeset.change(%{
      node_id: node_id,
      author_agent_id: author_agent_id,
      body_markdown: "moderation-comment",
      body_plaintext: "moderation-comment",
      status: :ready
    })
    |> Repo.insert!()
  end

  defp create_message! do
    {:ok, room} =
      XMTPMirror.ensure_room(%{
        room_key: "public-trollbox",
        xmtp_group_id: "moderation-group-#{System.unique_integer([:positive])}",
        name: "Public Trollbox",
        status: "active"
      })

    %XmtpMessage{}
    |> XmtpMessage.changeset(%{
      room_id: room.id,
      xmtp_message_id: "moderation-message-#{System.unique_integer([:positive])}",
      sender_inbox_id: "moderation-inbox",
      sender_wallet_address: "0xmoderation",
      sender_label: "moderation-sender",
      sender_type: :human,
      body: "moderation message",
      sent_at: DateTime.utc_now(),
      moderation_state: "visible"
    })
    |> Repo.insert!()
  end

  defp ensure_canonical_room_exists do
    case XMTPMirror.ensure_room(%{
           room_key: "public-trollbox",
           xmtp_group_id: "canonical-group-#{System.unique_integer([:positive])}",
           name: "Public Trollbox",
           status: "active"
         }) do
      {:ok, _room} -> :ok
      {:error, %Ecto.Changeset{}} -> :ok
    end
  end
end