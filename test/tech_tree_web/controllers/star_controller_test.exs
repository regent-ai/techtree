defmodule TechTreeWeb.StarControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import Ecto.Query

  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Repo
  alias TechTree.Stars.NodeStar

  test "requires SIWA auth", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/v1/tree/nodes/1/star", %{})
      |> json_response(401)

    assert %{"error" => %{"code" => "agent_auth_required"}} = response
  end

  test "create and delete star mutate node_stars", %{conn: conn} do
    headers = create_agent_headers!("star-controller")
    node = create_node!(headers.agent)
    agent_id = headers.agent.id

    create_response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes/#{node.id}/star", %{})
      |> json_response(200)

    assert %{
             "data" => %{
               "node_id" => node_id,
               "actor_type" => "agent",
               "actor_ref" => actor_ref
             }
           } = create_response

    assert node_id == node.id
    assert actor_ref == agent_id

    assert Repo.exists?(
             from(s in NodeStar,
               where:
                 s.node_id == ^node.id and s.actor_type == :agent and s.actor_ref == ^agent_id
             )
           )

    delete_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> delete("/v1/tree/nodes/#{node.id}/star")
      |> json_response(200)

    assert %{"ok" => true} = delete_response

    refute Repo.exists?(
             from(s in NodeStar,
               where:
                 s.node_id == ^node.id and s.actor_type == :agent and s.actor_ref == ^agent_id
             )
           )
  end

  test "duplicate create returns the persisted star row", %{conn: conn} do
    headers = create_agent_headers!("star-duplicate")
    node = create_node!(headers.agent)

    first_response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes/#{node.id}/star", %{})
      |> json_response(200)

    second_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> post("/v1/tree/nodes/#{node.id}/star", %{})
      |> json_response(200)

    assert first_response["data"]["id"] == second_response["data"]["id"]
    assert first_response["data"]["inserted_at"] == second_response["data"]["inserted_at"]
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
      title: "star-node-#{unique}",
      status: :anchored,
      notebook_source: "print('node')",
      publish_idempotency_key: "star-node:#{unique}",
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
