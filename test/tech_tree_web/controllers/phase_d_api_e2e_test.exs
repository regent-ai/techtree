defmodule TechTreeWeb.PhaseDApiE2ETest do
  use TechTreeWeb.ConnCase, async: false

  import Ecto.Query
  import TechTree.PhaseDApiSupport

  alias TechTree.Repo
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Nodes.Node
  alias TechTree.Watches.NodeWatcher
  alias TechTree.XMTPMirror.XmtpMembershipCommand

  setup do
    Process.put(:tech_tree_disable_rate_limits, true)

    privy = setup_privy_config!()

    on_exit(fn ->
      Process.delete(:tech_tree_disable_rate_limits)
      privy.restore.()
    end)

    {:ok, privy: privy}
  end

  test "covers Phase D API e2e flow across reads, auth writes, readiness, watches, chatbox, and moderation",
       %{privy: privy} do
    root_creator = create_agent!("phase-d-root")
    root_node = create_ready_node!(root_creator, title: "phase-d-root-#{unique_suffix()}")

    writer_wallet = random_eth_address()
    writer_registry = random_eth_address()
    writer_token_id = Integer.to_string(unique_suffix())

    writer_conn = fn ->
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(
        wallet: writer_wallet,
        chain_id: "11155111",
        registry_address: writer_registry,
        token_id: writer_token_id
      )
    end

    human = create_human!("phase-d-human", role: "user")
    admin = create_human!("phase-d-admin", role: "admin")

    human_conn = fn ->
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(human.privy_user_id, privy.app_id, privy.private_pem)
    end

    admin_conn = fn ->
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(admin.privy_user_id, privy.app_id, privy.private_pem)
    end

    assert %{"data" => index_nodes} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/tree/nodes")
             |> json_response(200)

    assert Enum.any?(index_nodes, &(&1["id"] == root_node.id))

    assert %{"data" => %{"id" => root_id}} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/tree/nodes/#{root_node.id}")
             |> json_response(200)

    assert root_id == root_node.id

    assert %{"data" => []} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/tree/nodes/#{root_node.id}/children")
             |> json_response(200)

    assert %{"data" => []} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/tree/nodes/#{root_node.id}/comments")
             |> json_response(200)

    node_idempotency_key = "phase-d-e2e-node:#{unique_suffix()}"

    assert %{
             "data" => %{
               "node_id" => child_node_id,
               "manifest_cid" => manifest_cid,
               "status" => "pinned",
               "anchor_status" => "pending"
             }
           } =
             writer_conn.()
             |> post("/v1/tree/nodes", %{
               "seed" => "ML",
               "kind" => "hypothesis",
               "title" => "phase-d-child-#{unique_suffix()}",
               "parent_id" => root_node.id,
               "notebook_source" => "print('phase d e2e child')",
               "idempotency_key" => node_idempotency_key
             })
             |> json_response(201)

    assert is_binary(manifest_cid) and manifest_cid != ""

    assert %{"data" => %{"node_id" => ^child_node_id}} =
             writer_conn.()
             |> post("/v1/tree/nodes", %{
               "seed" => "ML",
               "kind" => "hypothesis",
               "title" => "phase-d-child-retry-#{unique_suffix()}",
               "parent_id" => root_node.id,
               "notebook_source" => "print('phase d e2e child retry')",
               "idempotency_key" => node_idempotency_key
             })
             |> json_response(201)

    assert %{"data" => []} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/tree/nodes/#{root_node.id}/children")
             |> json_response(200)

    assert :ok = mark_node_ready_for_public!(child_node_id)
    assert :ok = force_public_visibility!(child_node_id)

    ready_children =
      await_ok("child node should become visible in public children feed", fn ->
        response =
          Phoenix.ConnTest.build_conn()
          |> put_req_header("accept", "application/json")
          |> get("/v1/tree/nodes/#{root_node.id}/children")
          |> json_response(200)

        data = Map.get(response, "data", [])

        if Enum.any?(data, &(&1["id"] == child_node_id and &1["status"] == "anchored")) do
          {:ok, data}
        else
          {:retry, data}
        end
      end)

    assert Enum.any?(ready_children, &(&1["id"] == child_node_id and &1["status"] == "anchored"))

    assert %{"data" => %{"id" => shown_child_id, "status" => "anchored"}} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/tree/nodes/#{child_node_id}")
             |> json_response(200)

    assert shown_child_id == child_node_id

    comment_idempotency_key = "phase-d-e2e-comment:#{unique_suffix()}"

    assert %{"data" => %{"comment_id" => comment_id, "node_id" => ^child_node_id}} =
             writer_conn.()
             |> post("/v1/tree/comments", %{
               "node_id" => child_node_id,
               "body_markdown" => "phase-d-comment-#{unique_suffix()}",
               "body_plaintext" => "phase-d-comment",
               "idempotency_key" => comment_idempotency_key
             })
             |> json_response(201)

    assert %{"data" => %{"comment_id" => ^comment_id}} =
             writer_conn.()
             |> post("/v1/tree/comments", %{
               "node_id" => child_node_id,
               "body_markdown" => "phase-d-comment-retry-#{unique_suffix()}",
               "body_plaintext" => "phase-d-comment-retry",
               "idempotency_key" => comment_idempotency_key
             })
             |> json_response(201)

    ready_comments =
      await_ok("comment should become visible in public comments feed", fn ->
        response =
          Phoenix.ConnTest.build_conn()
          |> put_req_header("accept", "application/json")
          |> get("/v1/tree/nodes/#{child_node_id}/comments")
          |> json_response(200)

        data = Map.get(response, "data", [])

        if Enum.any?(data, &(&1["id"] == comment_id and &1["status"] == "ready")) do
          {:ok, data}
        else
          {:retry, data}
        end
      end)

    assert Enum.any?(ready_comments, &(&1["id"] == comment_id and &1["status"] == "ready"))

    writer_agent_id = Repo.get!(Node, child_node_id).creator_agent_id

    assert %{"data" => %{"watcher_type" => "agent", "watcher_ref" => agent_ref}} =
             writer_conn.()
             |> post("/v1/tree/nodes/#{child_node_id}/watch", %{})
             |> json_response(200)

    assert agent_ref == writer_agent_id

    assert Repo.exists?(
             from(w in NodeWatcher,
               where:
                 w.node_id == ^child_node_id and w.watcher_type == :agent and
                   w.watcher_ref == ^writer_agent_id
             )
           )

    assert %{"ok" => true} =
             writer_conn.()
             |> delete("/v1/tree/nodes/#{child_node_id}/watch")
             |> json_response(200)

    refute Repo.exists?(
             from(w in NodeWatcher,
               where:
                 w.node_id == ^child_node_id and w.watcher_type == :agent and
                   w.watcher_ref == ^writer_agent_id
             )
           )

    _room = create_canonical_room!()

    visible_message =
      create_chatbox_message!(human, %{
        body: "phase-d-chatbox-#{unique_suffix()}"
      })

    assert %{"data" => public_messages} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/chatbox/messages")
             |> json_response(200)

    assert Enum.any?(public_messages, &(&1["id"] == visible_message.id))

    assert %{"data" => %{"room_present" => true, "state" => "not_joined"}} =
             human_conn.()
             |> get("/v1/chatbox/membership")
             |> json_response(200)

    assert %{"data" => %{"status" => "pending", "human_id" => requested_human_id}} =
             human_conn.()
             |> post("/v1/chatbox/request-join", %{})
             |> json_response(200)

    assert requested_human_id == human.id

    assert %{"data" => %{"room_present" => true, "state" => "join_pending"}} =
             human_conn.()
             |> get("/v1/chatbox/membership")
             |> json_response(200)

    assert %{"ok" => true} =
             admin_conn.()
             |> post("/v1/admin/chatbox/members/#{human.id}/add", %{})
             |> json_response(200)

    assert_eventually_true("add_member command should persist", fn ->
      Repo.exists?(
        from(c in XmtpMembershipCommand,
          where: c.human_user_id == ^human.id and c.op == "add_member"
        )
      )
    end)

    {latest_add_command_id, latest_add_inbox_id} =
      Repo.one!(
        from(c in XmtpMembershipCommand,
          where: c.human_user_id == ^human.id and c.op == "add_member",
          order_by: [desc: c.inserted_at, desc: c.id],
          limit: 1,
          select: {c.id, c.xmtp_inbox_id}
        )
      )

    _ =
      Repo.update_all(
        from(c in XmtpMembershipCommand, where: c.id == ^latest_add_command_id),
        set: [status: "done", xmtp_inbox_id: latest_add_inbox_id]
      )

    assert %{"data" => %{"state" => "joined"}} =
             human_conn.()
             |> get("/v1/chatbox/membership")
             |> json_response(200)

    assert %{"data" => %{"body" => posted_body, "author_kind" => "human"}} =
             human_conn.()
             |> post("/v1/chatbox/messages", %{
               "body" => "phase-d-human-post-#{unique_suffix()}"
             })
             |> json_response(201)

    assert String.starts_with?(posted_body, "phase-d-human-post-")

    assert %{"ok" => true} =
             admin_conn.()
             |> post("/v1/admin/chatbox/members/#{human.id}/remove", %{})
             |> json_response(200)

    assert_eventually_true("remove_member command should persist", fn ->
      Repo.exists?(
        from(c in XmtpMembershipCommand,
          where: c.human_user_id == ^human.id and c.op == "remove_member"
        )
      )
    end)

    assert %{"ok" => true} =
             admin_conn.()
             |> post("/v1/admin/chatbox/messages/#{visible_message.id}/hide", %{
               "reason" => "phase-d-hide-message"
             })
             |> json_response(200)

    moderated_messages =
      await_ok("moderated message should disappear from public chatbox feed", fn ->
        response =
          Phoenix.ConnTest.build_conn()
          |> put_req_header("accept", "application/json")
          |> get("/v1/chatbox/messages")
          |> json_response(200)

        data = Map.get(response, "data", [])

        if Enum.any?(data, &(&1["id"] == visible_message.id)) do
          {:retry, data}
        else
          {:ok, data}
        end
      end)

    refute Enum.any?(moderated_messages, &(&1["id"] == visible_message.id))

    assert %{"ok" => true} =
             admin_conn.()
             |> post("/v1/admin/agents/#{writer_agent_id}/ban", %{
               "reason" => "phase-d-ban-agent"
             })
             |> json_response(200)

    children_after_ban =
      await_ok("banned agent child node should disappear from parent children feed", fn ->
        response =
          Phoenix.ConnTest.build_conn()
          |> put_req_header("accept", "application/json")
          |> get("/v1/tree/nodes/#{root_node.id}/children")
          |> json_response(200)

        data = Map.get(response, "data", [])

        if Enum.any?(data, &(&1["id"] == child_node_id)) do
          {:retry, data}
        else
          {:ok, data}
        end
      end)

    refute Enum.any?(children_after_ban, &(&1["id"] == child_node_id))

    await_ok("banned node detail should return 404", fn ->
      hidden_node_conn =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("accept", "application/json")
        |> get("/v1/tree/nodes/#{child_node_id}")

      if hidden_node_conn.status == 404 do
        {:ok, :not_found}
      else
        {:retry, hidden_node_conn.status}
      end
    end)

    assert %{"data" => []} =
             await_ok("comments under banned node should be hidden from public view", fn ->
               response =
                 Phoenix.ConnTest.build_conn()
                 |> put_req_header("accept", "application/json")
                 |> get("/v1/tree/nodes/#{child_node_id}/comments")
                 |> json_response(200)

               data = Map.get(response, "data", [])
               if data == [], do: {:ok, response}, else: {:retry, data}
             end)
  end

  defp force_public_visibility!(node_id) do
    node = Repo.get!(Node, node_id)

    Node
    |> where([n], n.id == ^node_id)
    |> Repo.update_all(set: [status: :anchored])

    AgentIdentity
    |> where([a], a.id == ^node.creator_agent_id)
    |> Repo.update_all(set: [status: "active"])

    :ok
  end

  defp await_ok(description, fun, attempts \\ 20, delay_ms \\ 40) when is_function(fun, 0) do
    case fun.() do
      {:ok, result} ->
        result

      {:retry, _context} when attempts > 1 ->
        wait_ms(delay_ms)
        await_ok(description, fun, attempts - 1, delay_ms)

      {:retry, context} ->
        flunk("timeout: #{description}; last context=#{inspect(context)}")

      other ->
        flunk("invalid await result for '#{description}': #{inspect(other)}")
    end
  end

  defp assert_eventually_true(description, fun, attempts \\ 20, delay_ms \\ 40)
       when is_function(fun, 0) do
    await_ok(
      description,
      fn ->
        if fun.() do
          {:ok, true}
        else
          {:retry, false}
        end
      end,
      attempts,
      delay_ms
    )
  end

  defp wait_ms(delay_ms) when is_integer(delay_ms) and delay_ms >= 0 do
    receive do
    after
      delay_ms -> :ok
    end
  end
end
