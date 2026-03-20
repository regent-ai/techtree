defmodule TechTreeWeb.AgentNodeControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import Ecto.Query

  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  setup do
    Process.put(:tech_tree_disable_rate_limits, true)

    on_exit(fn ->
      Process.delete(:tech_tree_disable_rate_limits)
    end)

    :ok
  end

  test "POST /v1/tree/nodes returns pinned artifact and idempotent retries return same node", %{
    conn: conn
  } do
    headers = create_agent_headers!("agent-node")
    parent = create_public_parent!(headers.agent)

    related =
      create_public_node!(headers.agent, parent_id: parent.id, title: "agent-node-related")

    idempotency_key = "agent-node:#{System.unique_integer([:positive])}"

    first_response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "agent-node-first",
        "parent_id" => parent.id,
        "notebook_source" => "print('agent node first')",
        "sidelinks" => [%{"node_id" => related.id, "tag" => "supports", "ordinal" => 2}],
        "idempotency_key" => idempotency_key
      })
      |> json_response(201)

    assert %{
             "data" => %{
               "node_id" => node_id,
               "manifest_cid" => manifest_cid,
               "status" => "pinned",
               "anchor_status" => "pending"
             }
           } = first_response

    assert has_text?(manifest_cid)

    second_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "agent-node-second",
        "parent_id" => parent.id,
        "notebook_source" => "print('agent node second')",
        "idempotency_key" => idempotency_key
      })
      |> json_response(201)

    assert %{
             "data" => %{
               "node_id" => ^node_id,
               "manifest_cid" => ^manifest_cid,
               "status" => "pinned",
               "anchor_status" => "pending"
             }
           } = second_response

    persisted = Repo.get!(Node, node_id)
    assert persisted.parent_id == parent.id
    assert persisted.status == :pinned
    assert persisted.manifest_cid == manifest_cid

    assert %{
             "data" => %{
               "id" => ^node_id,
               "manifest_cid" => ^manifest_cid,
               "status" => "pinned",
               "sidelinks" => [
                 %{"dst_node_id" => related_id, "tag" => "supports", "ordinal" => 2}
               ]
             }
           } =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(headers)
             |> get("/v1/agent/tree/nodes/#{node_id}")
             |> json_response(200)

    assert related_id == related.id

    assert %{"data" => children} =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(headers)
             |> get("/v1/agent/tree/nodes/#{parent.id}/children")
             |> json_response(200)

    assert Enum.any?(children, &(&1["id"] == node_id and &1["status"] == "pinned"))

    assert %{"data" => public_children} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/tree/nodes/#{parent.id}/children")
             |> json_response(200)

    refute Enum.any?(public_children, &(&1["id"] == node_id))
    assert Enum.any?(public_children, &(&1["id"] == related.id and &1["status"] == "anchored"))

    assert Repo.aggregate(
             from(n in Node, where: n.publish_idempotency_key == ^idempotency_key),
             :count,
             :id
           ) == 1
  end

  test "POST /v1/tree/nodes pin failure does not leave a node row", %{conn: conn} do
    headers = create_agent_headers!("agent-node-pin-failure")
    parent = create_public_parent!(headers.agent)
    idempotency_key = "agent-node-pin-failure:#{System.unique_integer([:positive])}"

    previous_lighthouse_cfg = Application.get_env(:tech_tree, TechTree.IPFS.LighthouseClient)

    on_exit(fn ->
      Application.put_env(:tech_tree, TechTree.IPFS.LighthouseClient, previous_lighthouse_cfg)
    end)

    Application.put_env(:tech_tree, TechTree.IPFS.LighthouseClient, mock_uploads: false)

    response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "agent-node-pin-failure",
        "parent_id" => parent.id,
        "notebook_source" => "print('agent node pin failure')",
        "idempotency_key" => idempotency_key
      })
      |> json_response(422)

    assert %{"error" => %{"code" => "node_create_failed"}} = response

    refute Repo.exists?(from(n in Node, where: n.publish_idempotency_key == ^idempotency_key))
  end

  test "POST /v1/tree/nodes rejects unanchored parents", %{conn: conn} do
    headers = create_agent_headers!("agent-node-unanchored-parent")
    parent = create_public_parent!(headers.agent, status: :pinned)

    response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "agent-node-unanchored-parent",
        "parent_id" => parent.id,
        "notebook_source" => "print('agent node unanchored parent')",
        "idempotency_key" => "agent-node-unanchored-parent:#{System.unique_integer([:positive])}"
      })
      |> json_response(422)

    assert %{"error" => %{"code" => "parent_not_anchored"}} = response
  end

  test "POST /v1/tree/nodes rate limits repeated non-idempotent creates per agent", %{conn: conn} do
    headers = create_agent_headers!("agent-node-rate-limit")
    parent = create_public_parent!(headers.agent)

    assert %{"data" => %{"node_id" => _node_id}} =
             conn
             |> with_siwa_headers(headers)
             |> post("/v1/tree/nodes", %{
               "seed" => "ML",
               "kind" => "hypothesis",
               "title" => "agent-node-rate-limit-first",
               "parent_id" => parent.id,
               "notebook_source" => "print('agent node rate limit first')"
             })
             |> json_response(201)

    assert %{
             "error" => %{
               "code" => "node_create_rate_limited",
               "retry_after_ms" => retry_after_ms
             }
           } =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(headers)
             |> post("/v1/tree/nodes", %{
               "seed" => "ML",
               "kind" => "hypothesis",
               "title" => "agent-node-rate-limit-second",
               "parent_id" => parent.id,
               "notebook_source" => "print('agent node rate limit second')"
             })
             |> json_response(429)

    assert is_integer(retry_after_ms)
    assert retry_after_ms > 0
  end

  defp create_agent_headers!(label_prefix) do
    unique = System.unique_integer([:positive])

    wallet = random_eth_address()
    registry = random_eth_address()
    token_id = Integer.to_string(unique)

    agent =
      Agents.upsert_verified_agent!(%{
        "chain_id" => "11155111",
        "registry_address" => registry,
        "token_id" => token_id,
        "wallet_address" => wallet,
        "label" => "#{label_prefix}-#{unique}"
      })

    %{agent: agent, wallet: wallet, chain_id: "11155111", registry: registry, token_id: token_id}
  end

  defp with_siwa_headers(conn, headers) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-agent-wallet-address", headers.wallet)
    |> put_req_header("x-agent-chain-id", headers.chain_id)
    |> put_req_header("x-agent-registry-address", headers.registry)
    |> put_req_header("x-agent-token-id", headers.token_id)
  end

  defp create_public_parent!(creator, attrs \\ []) do
    unique = System.unique_integer([:positive])

    %Node{}
    |> Ecto.Changeset.change(%{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "agent-node-parent-#{unique}",
      status: Keyword.get(attrs, :status, :anchored),
      notebook_source: "print('parent')",
      publish_idempotency_key: "agent-node-parent:#{unique}",
      creator_agent_id: creator.id
    })
    |> Repo.insert!()
  end

  defp create_public_node!(creator, attrs) do
    unique = System.unique_integer([:positive])

    %Node{}
    |> Ecto.Changeset.change(%{
      path: "n#{unique}",
      depth: Keyword.get(attrs, :depth, 1),
      seed: Keyword.get(attrs, :seed, "ML"),
      kind: Keyword.get(attrs, :kind, :hypothesis),
      title: Keyword.get(attrs, :title, "agent-node-#{unique}"),
      status: Keyword.get(attrs, :status, :anchored),
      parent_id: Keyword.get(attrs, :parent_id),
      notebook_source: Keyword.get(attrs, :notebook_source, "print('node')"),
      publish_idempotency_key: "agent-node:#{unique}",
      creator_agent_id: creator.id
    })
    |> Repo.insert!()
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end

  defp has_text?(value) when is_binary(value), do: byte_size(String.trim(value)) > 0
  defp has_text?(_value), do: false
end
