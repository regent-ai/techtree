defmodule TechTreeWeb.AgentPhase2AcceptanceTest do
  use TechTreeWeb.ConnCase, async: false

  import Ecto.Query

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Repo

  test "agent writes require SIWA auth headers", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/v1/tree/nodes", %{})

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)
  end

  test "agent node creation requires notebook_source", %{conn: conn} do
    conn =
      conn
      |> with_siwa_headers()
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "Phase 2 notebook check",
        "parent_id" => 999_999
      })

    assert %{"error" => %{"code" => "notebook_source_required"}} = json_response(conn, 422)
  end

  test "agent node creation reuses the same agent identity even when repeated writes are throttled" do
    wallet = random_eth_address()
    registry = random_eth_address()
    token_id = Integer.to_string(System.unique_integer([:positive]))

    params = %{
      "seed" => "ML",
      "kind" => "hypothesis",
      "title" => "Phase 2 retry",
      "parent_id" => 999_999,
      "notebook_source" => "print('phase2')"
    }

    first_conn =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(wallet: wallet, registry_address: registry, token_id: token_id)
      |> post("/v1/tree/nodes", params)

    assert %{"error" => %{"code" => "parent_not_found"}} = json_response(first_conn, 422)

    first_agent =
      Repo.one!(
        from(a in AgentIdentity,
          where:
            a.wallet_address == ^wallet and a.chain_id == 8_453 and
              a.registry_address == ^registry,
          order_by: [desc: a.inserted_at],
          limit: 1
        )
      )

    second_conn =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(wallet: wallet, registry_address: registry, token_id: token_id)
      |> post("/v1/tree/nodes", params)

    assert %{
             "error" => %{
               "code" => "node_create_rate_limited",
               "retry_after_ms" => retry_after_ms
             }
           } =
             json_response(second_conn, 429)

    assert is_integer(retry_after_ms)
    assert retry_after_ms > 0

    second_agent = Repo.get!(AgentIdentity, first_agent.id)
    assert second_agent.id == first_agent.id

    assert DateTime.compare(second_agent.last_verified_at, first_agent.last_verified_at) in [
             :eq,
             :gt
           ]
  end

  defp with_siwa_headers(conn, opts \\ []) do
    unique = System.unique_integer([:positive])

    wallet = Keyword.get(opts, :wallet, random_eth_address())
    chain_id = Keyword.get(opts, :chain_id, "8453")
    registry = Keyword.get(opts, :registry_address, random_eth_address())
    token_id = Keyword.get(opts, :token_id, Integer.to_string(unique))

    TechTreeWeb.TestSupport.SiwaIntegrationSupport.with_siwa_headers(conn,
      wallet: wallet,
      chain_id: chain_id,
      registry_address: registry,
      token_id: token_id
    )
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end
end
