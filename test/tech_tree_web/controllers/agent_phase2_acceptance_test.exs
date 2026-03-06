defmodule TechTreeWeb.AgentPhase2AcceptanceTest do
  use TechTreeWeb.ConnCase, async: false

  import Ecto.Query

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Repo

  setup do
    Process.put(:tech_tree_disable_rate_limits, true)

    on_exit(fn ->
      Process.delete(:tech_tree_disable_rate_limits)
    end)

    :ok
  end

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

  test "agent node creation returns rate_limited after initial write attempt" do
    Process.delete(:tech_tree_disable_rate_limits)

    try do
      wallet = random_eth_address()
      registry = random_eth_address()
      token_id = Integer.to_string(System.unique_integer([:positive]))

      params = %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "Phase 2 rate limit",
        "parent_id" => 999_999,
        "notebook_source" => "print('phase2')"
      }

      first_conn =
        Phoenix.ConnTest.build_conn()
        |> with_siwa_headers(wallet: wallet, registry_address: registry, token_id: token_id)
        |> post("/v1/tree/nodes", params)

      if dragonfly_available?() do
        assert %{"error" => %{"code" => "parent_not_found"}} = json_response(first_conn, 422)

        first_agent =
          Repo.one!(
            from(a in AgentIdentity,
              where:
                a.wallet_address == ^wallet and a.chain_id == 8453 and
                  a.registry_address == ^registry,
              order_by: [desc: a.inserted_at],
              limit: 1
            )
          )

        second_conn =
          Phoenix.ConnTest.build_conn()
          |> with_siwa_headers(wallet: wallet, registry_address: registry, token_id: token_id)
          |> post("/v1/tree/nodes", params)

        assert %{"error" => %{"code" => "rate_limited"}} = json_response(second_conn, 429)

        second_agent = Repo.get!(AgentIdentity, first_agent.id)
        assert second_agent.last_verified_at == first_agent.last_verified_at
      else
        assert %{"error" => %{"code" => "rate_limited"}} = json_response(first_conn, 429)
      end
    after
      Process.put(:tech_tree_disable_rate_limits, true)
    end
  end

  defp with_siwa_headers(conn, opts \\ []) do
    unique = System.unique_integer([:positive])

    wallet = Keyword.get(opts, :wallet, random_eth_address())
    chain_id = Keyword.get(opts, :chain_id, "8453")
    registry = Keyword.get(opts, :registry_address, random_eth_address())
    token_id = Keyword.get(opts, :token_id, Integer.to_string(unique))

    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-agent-wallet-address", wallet)
    |> put_req_header("x-agent-chain-id", chain_id)
    |> put_req_header("x-agent-registry-address", registry)
    |> put_req_header("x-agent-token-id", token_id)
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end

  defp dragonfly_available? do
    case Redix.command(:dragonfly, ["PING"]) do
      {:ok, "PONG"} -> true
      _ -> false
    end
  rescue
    _ -> false
  catch
    :exit, _reason -> false
  end
end
