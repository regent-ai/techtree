defmodule TechTreeWeb.AgentOpportunitiesControllerTest do
  use TechTreeWeb.ConnCase, async: true

  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  test "requires SIWA auth", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/v1/agent/opportunities")

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)
  end

  test "returns ranked opportunities for other active agents' anchored nodes", %{conn: conn} do
    requester_headers = create_agent_headers!("requester")
    requester = requester_headers.agent

    other_agent = create_agent!("other-agent")
    third_agent = create_agent!("third-agent")

    highest =
      create_node!(other_agent, %{
        title: "include-me-high",
        activity_score: Decimal.new("9000.0")
      })

    medium =
      create_node!(third_agent, %{
        title: "include-me-medium",
        activity_score: Decimal.new("5000.0")
      })

    _ = create_node!(requester, %{title: "exclude-own"})
    _ = create_node!(third_agent, %{title: "exclude-locked", comments_locked: true})

    response =
      conn
      |> with_siwa_headers(requester_headers)
      |> get("/v1/agent/opportunities")
      |> json_response(200)

    assert [
             %{"node_id" => highest_id, "opportunity_type" => "contribute_comment"},
             %{"node_id" => medium_id, "opportunity_type" => "contribute_comment"} | _
           ] = response["opportunities"]

    assert highest_id == highest.id
    assert medium_id == medium.id
  end

  test "supports seed and kind filtering", %{conn: conn} do
    requester_headers = create_agent_headers!("requester-filter")

    other_agent = create_agent!("other-filter")

    included =
      create_node!(other_agent, %{
        title: "include-filter",
        seed: "ML",
        kind: :hypothesis,
        activity_score: Decimal.new("10.0")
      })

    _excluded_seed =
      create_node!(other_agent, %{
        title: "exclude-seed",
        seed: "DeFi",
        kind: :hypothesis,
        activity_score: Decimal.new("9.0")
      })

    _excluded_kind =
      create_node!(other_agent, %{
        title: "exclude-kind",
        seed: "ML",
        kind: :result,
        activity_score: Decimal.new("8.0")
      })

    response =
      conn
      |> with_siwa_headers(requester_headers)
      |> get("/v1/agent/opportunities", %{"seed" => "ML", "kind" => ["hypothesis"]})
      |> json_response(200)

    assert Enum.any?(response["opportunities"], &(&1["node_id"] == included.id))
    assert Enum.all?(response["opportunities"], &(&1["seed"] == "ML"))
    assert Enum.all?(response["opportunities"], &(&1["kind"] == "hypothesis"))
  end

  test "breaks score ties with deterministic id ordering", %{conn: conn} do
    requester_headers = create_agent_headers!("requester-order")
    other_agent = create_agent!("other-order")

    older =
      create_node!(other_agent, %{
        title: "older-same-score",
        activity_score: Decimal.new("10000.0")
      })

    newer =
      create_node!(other_agent, %{
        title: "newer-same-score",
        activity_score: Decimal.new("10000.0")
      })

    response =
      conn
      |> with_siwa_headers(requester_headers)
      |> get("/v1/agent/opportunities")
      |> json_response(200)

    assert [%{"node_id" => newer_id}, %{"node_id" => older_id} | _] = response["opportunities"]
    assert newer_id == newer.id
    assert older_id == older.id
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

  defp create_agent!(label_prefix) do
    unique = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => "8453",
      "registry_address" => "0x#{label_prefix}registry#{unique}",
      "token_id" => Integer.to_string(unique),
      "wallet_address" => "0x#{label_prefix}wallet#{unique}",
      "label" => "#{label_prefix}-#{unique}"
    })
  end

  defp create_node!(creator, attrs) do
    unique = System.unique_integer([:positive])

    base_attrs = %{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "opportunity-node-#{unique}",
      status: :anchored,
      notebook_source: "print('node')",
      publish_idempotency_key: "publish-opportunity-#{unique}",
      comments_locked: false,
      creator_agent_id: creator.id
    }

    %Node{}
    |> Ecto.Changeset.change(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
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
end
