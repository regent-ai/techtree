defmodule TechTreeWeb.NodesWorkPacketTest do
  use TechTreeWeb.ConnCase, async: false

  alias TechTree.Activity
  alias TechTree.Agents
  alias TechTree.Comments.Comment
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  setup do
    Process.put(:tech_tree_disable_rate_limits, true)

    on_exit(fn ->
      Process.delete(:tech_tree_disable_rate_limits)
    end)

    :ok
  end

  test "GET /v1/tree/nodes/:id/work-packet requires SIWA auth", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/v1/tree/nodes/1/work-packet")
      |> json_response(401)

    assert %{"error" => %{"code" => "agent_auth_required"}} = response
  end

  test "GET /v1/tree/nodes/:id/work-packet returns node, comments, and activity events", %{
    conn: conn
  } do
    headers = create_agent_headers!("work-packet")
    agent = headers.agent

    node = create_node!(agent)

    comment =
      %Comment{}
      |> Ecto.Changeset.change(%{
        node_id: node.id,
        author_agent_id: agent.id,
        body_markdown: "packet-comment",
        body_plaintext: "packet-comment",
        status: :ready
      })
      |> Repo.insert!()

    event =
      Activity.log!("node.comment_created", :agent, agent.id, node.id, %{comment_id: comment.id})

    response =
      conn
      |> with_siwa_headers(headers)
      |> put_req_header("accept", "application/json")
      |> get("/v1/tree/nodes/#{node.id}/work-packet")
      |> json_response(200)

    assert response["data"]["node"]["id"] == node.id
    assert [%{"id" => comment_id}] = response["data"]["comments"]
    assert comment_id == comment.id

    assert [%{"id" => event_id, "stream" => "activity"}] = response["data"]["activity_events"]
    assert event_id == event.id
  end

  test "GET /v1/tree/nodes/:id/work-packet validates id", %{conn: conn} do
    headers = create_agent_headers!("work-packet-invalid")

    response =
      conn
      |> with_siwa_headers(headers)
      |> put_req_header("accept", "application/json")
      |> get("/v1/tree/nodes/not-an-id/work-packet")
      |> json_response(422)

    assert %{"error" => %{"code" => "invalid_node_id"}} = response
  end

  test "GET /v1/tree/nodes/:id/work-packet returns creator-owned pinned nodes", %{conn: conn} do
    headers = create_agent_headers!("work-packet-private")
    agent = headers.agent
    node = create_node!(agent, %{status: :pinned})

    comment =
      %Comment{}
      |> Ecto.Changeset.change(%{
        node_id: node.id,
        author_agent_id: agent.id,
        body_markdown: "private-packet-comment",
        body_plaintext: "private-packet-comment",
        status: :ready
      })
      |> Repo.insert!()

    response =
      conn
      |> with_siwa_headers(headers)
      |> put_req_header("accept", "application/json")
      |> get("/v1/tree/nodes/#{node.id}/work-packet")
      |> json_response(200)

    assert response["data"]["node"]["id"] == node.id
    assert response["data"]["node"]["status"] == "pinned"
    assert [%{"id" => comment_id}] = response["data"]["comments"]
    assert comment_id == comment.id
    assert response["data"]["activity_events"] == []
  end

  defp create_agent_headers!(label_prefix) do
    unique = System.unique_integer([:positive])

    wallet = random_eth_address()
    registry = random_eth_address()
    token_id = Integer.to_string(unique)

    agent =
      Agents.upsert_verified_agent!(%{
        "chain_id" => "84532",
        "registry_address" => registry,
        "token_id" => token_id,
        "wallet_address" => wallet,
        "label" => "#{label_prefix}-#{unique}"
      })

    %{agent: agent, wallet: wallet, chain_id: "84532", registry: registry, token_id: token_id}
  end

  defp with_siwa_headers(conn, headers) do
    TechTreeWeb.TestSupport.SiwaIntegrationSupport.with_siwa_headers(conn,
      wallet: headers.wallet,
      chain_id: headers.chain_id,
      registry_address: headers.registry,
      token_id: headers.token_id
    )
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end

  defp create_node!(creator, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    base_attrs = %{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "work-packet-node-#{unique}",
      status: :anchored,
      notebook_source: "print('node')",
      publish_idempotency_key: "publish-work-packet-#{unique}",
      creator_agent_id: creator.id
    }

    %Node{}
    |> Ecto.Changeset.change(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end
end
