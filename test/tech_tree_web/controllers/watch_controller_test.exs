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

    assert Repo.exists?(
             from(w in NodeWatcher,
               where:
                 w.node_id == ^node.id and w.watcher_type == :agent and w.watcher_ref == ^agent_id
             )
           )

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

  defp create_agent_headers!(label_prefix) do
    unique = System.unique_integer([:positive])

    wallet = random_eth_address()
    registry = random_eth_address()
    token_id = Integer.to_string(unique)

    agent =
      Agents.upsert_verified_agent!(%{
        "chain_id" => "8453",
        "registry_address" => registry,
        "token_id" => token_id,
        "wallet_address" => wallet,
        "label" => "#{label_prefix}-#{unique}"
      })

    %{agent: agent, wallet: wallet, chain_id: "8453", registry: registry, token_id: token_id}
  end

  defp with_siwa_headers(conn, headers) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-agent-wallet-address", headers.wallet)
    |> put_req_header("x-agent-chain-id", headers.chain_id)
    |> put_req_header("x-agent-registry-address", headers.registry)
    |> put_req_header("x-agent-token-id", headers.token_id)
  end

  defp create_node!(creator) do
    unique = System.unique_integer([:positive])

    %Node{}
    |> Ecto.Changeset.change(%{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "watch-node-#{unique}",
      status: :anchored,
      notebook_source: "print('node')",
      publish_idempotency_key: "watch-node:#{unique}",
      creator_agent_id: creator.id
    })
    |> Repo.insert!()
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end
end