defmodule TechTreeWeb.AgentInboxControllerTest do
  use TechTreeWeb.ConnCase, async: true

  alias TechTree.Activity
  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  test "requires SIWA auth", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/v1/agent/inbox")

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)
  end

  test "returns hard-cutover inbox shape with classified stream events", %{conn: conn} do
    headers = create_agent_headers!("inbox-controller")
    agent = headers.agent
    node = create_node!(agent)

    _ = Activity.log!("node.created", :agent, agent.id, node.id, %{seed: "ML"})
    _ = Activity.log!("economic.reward_earned", :agent, agent.id, nil, %{})
    _ = Activity.log!("node.comment_created", :agent, agent.id, node.id, %{})

    response =
      conn
      |> with_siwa_headers(headers)
      |> get("/v1/agent/inbox")
      |> json_response(200)

    assert Enum.sort(Map.keys(response)) == ["events", "next_cursor"]

    refute Map.has_key?(response, "data")
    refute Map.has_key?(response, "activity_events")
    refute Map.has_key?(response, "economic_events")
    refute Map.has_key?(response, "pending_actions")

    assert response["events"]
           |> Enum.map(&{&1["event_type"], &1["stream"]})
           |> MapSet.new() ==
             MapSet.new([
               {"node.created", "activity"},
               {"node.comment_created", "activity"},
               {"economic.reward_earned", "economic"}
             ])

    assert response["next_cursor"] ==
             response["events"] |> Enum.map(& &1["id"]) |> Enum.max()
  end

  test "supports seed scoping and cursor polling", %{conn: conn} do
    headers = create_agent_headers!("inbox-controller-filter")
    agent = headers.agent

    ml_node = create_node!(agent, %{seed: "ML"})
    defi_node = create_node!(agent, %{seed: "DeFi"})

    first_event = Activity.log!("node.created", :agent, agent.id, ml_node.id, %{seed: "ML"})
    _ = Activity.log!("node.created", :agent, agent.id, defi_node.id, %{seed: "DeFi"})
    second_ml_event = Activity.log!("node.comment_created", :agent, agent.id, ml_node.id, %{})

    response =
      conn
      |> with_siwa_headers(headers)
      |> get("/v1/agent/inbox", %{"seed" => "ML", "cursor" => Integer.to_string(first_event.id)})
      |> json_response(200)

    assert [
             %{
               "event_type" => "node.comment_created",
               "id" => second_event_id,
               "stream" => "activity"
             }
           ] = response["events"]

    assert second_event_id == second_ml_event.id
    assert response["next_cursor"] == second_ml_event.id

    next_response =
      conn
      |> with_siwa_headers(headers)
      |> get("/v1/agent/inbox", %{
        "seed" => "ML",
        "cursor" => Integer.to_string(response["next_cursor"])
      })
      |> json_response(200)

    assert next_response["events"] == []
    assert next_response["next_cursor"] == response["next_cursor"]
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
      title: "inbox-node-#{unique}",
      status: :anchored,
      notebook_source: "print('node')",
      publish_idempotency_key: "inbox-controller-node:#{unique}",
      creator_agent_id: creator.id
    }

    %Node{}
    |> Ecto.Changeset.change(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end
end
