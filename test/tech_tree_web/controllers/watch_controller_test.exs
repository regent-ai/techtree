defmodule TechTreeWeb.WatchControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import Ecto.Query

  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Repo
  alias TechTree.Watches.NodeWatcher

  test "requires SIWA auth", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/v1/tree/nodes/1/watch", %{})
      |> json_response(401)

    assert %{"error" => %{"code" => "agent_auth_required"}} = response
  end

  test "create and delete watch mutate node_watchers", %{conn: conn} do
    headers = create_agent_headers!("watch-controller")
    node = create_node!(headers.agent)
    agent_id = headers.agent.id

    create_response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes/#{node.id}/watch", %{})
      |> json_response(200)

    assert %{
             "data" => %{
               "node_id" => node_id,
               "watcher_type" => "agent",
               "watcher_ref" => watcher_ref
             }
           } =
             create_response

    assert node_id == node.id
    assert watcher_ref == agent_id
    assert is_integer(create_response["data"]["id"])
    assert is_binary(create_response["data"]["inserted_at"])

    assert Repo.exists?(
             from(w in NodeWatcher,
               where:
                 w.node_id == ^node.id and w.watcher_type == :agent and w.watcher_ref == ^agent_id
             )
           )

    assert Repo.get!(Node, node.id).watcher_count == 1

    delete_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> delete("/v1/tree/nodes/#{node.id}/watch")
      |> json_response(200)

    assert %{"ok" => true} = delete_response

    refute Repo.exists?(
             from(w in NodeWatcher,
               where:
                 w.node_id == ^node.id and w.watcher_type == :agent and w.watcher_ref == ^agent_id
             )
           )

    assert Repo.get!(Node, node.id).watcher_count == 0
  end

  test "duplicate create returns the persisted watch row", %{conn: conn} do
    headers = create_agent_headers!("watch-duplicate")
    node = create_node!(headers.agent)

    first_response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes/#{node.id}/watch", %{})
      |> json_response(200)

    second_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes/#{node.id}/watch", %{})
      |> json_response(200)

    assert first_response["data"]["id"] == second_response["data"]["id"]
    assert first_response["data"]["inserted_at"] == second_response["data"]["inserted_at"]
    assert Repo.get!(Node, node.id).watcher_count == 1
  end

  test "index returns current agent watches", %{conn: conn} do
    headers = create_agent_headers!("watch-index")
    first_node = create_node!(headers.agent)
    second_node = create_node!(headers.agent)

    conn
    |> with_siwa_headers(headers)
    |> post("/v1/tree/nodes/#{first_node.id}/watch", %{})
    |> json_response(200)

    Phoenix.ConnTest.build_conn()
    |> with_siwa_headers(headers)
    |> post("/v1/tree/nodes/#{second_node.id}/watch", %{})
    |> json_response(200)

    response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> get("/v1/agent/watches")
      |> json_response(200)

    assert Enum.sort(Enum.map(response["data"], & &1["node_id"])) ==
             Enum.sort([first_node.id, second_node.id])
  end

  test "watch create accepts pinned, hidden, and deleted nodes", %{conn: conn} do
    headers = create_agent_headers!("watch-any-node")
    pinned_node = create_node!(headers.agent, %{status: :pinned})
    hidden_node = create_node!(headers.agent, %{status: :hidden})
    deleted_node = create_node!(headers.agent, %{status: :deleted})

    pinned_response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes/#{pinned_node.id}/watch", %{})
      |> json_response(200)

    hidden_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes/#{hidden_node.id}/watch", %{})
      |> json_response(200)

    deleted_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes/#{deleted_node.id}/watch", %{})
      |> json_response(200)

    assert pinned_response["data"]["node_id"] == pinned_node.id
    assert hidden_response["data"]["node_id"] == hidden_node.id
    assert deleted_response["data"]["node_id"] == deleted_node.id
    assert Repo.get!(Node, pinned_node.id).watcher_count == 1
    assert Repo.get!(Node, hidden_node.id).watcher_count == 1
    assert Repo.get!(Node, deleted_node.id).watcher_count == 1
  end

  test "returns 422 for invalid node id on create and delete", %{conn: conn} do
    headers = create_agent_headers!("watch-invalid-id")

    create_response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes/not-a-number/watch", %{})
      |> json_response(422)

    assert %{"error" => %{"code" => "invalid_node_id"}} = create_response

    delete_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> delete("/v1/tree/nodes/not-a-number/watch")
      |> json_response(422)

    assert %{"error" => %{"code" => "invalid_node_id"}} = delete_response
  end

  test "returns 404 for missing node id on create and delete", %{conn: conn} do
    headers = create_agent_headers!("watch-missing-node")

    create_response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes/99999999/watch", %{})
      |> json_response(404)

    assert %{"error" => %{"code" => "node_not_found"}} = create_response

    delete_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> delete("/v1/tree/nodes/99999999/watch")
      |> json_response(404)

    assert %{"error" => %{"code" => "node_not_found"}} = delete_response
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

  defp create_node!(creator, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    base_attrs = %{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "watch-node-#{unique}",
      status: :anchored,
      notebook_source: "print('node')",
      publish_idempotency_key: "watch-node:#{unique}",
      creator_agent_id: creator.id
    }

    %Node{}
    |> Ecto.Changeset.change(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end
end
