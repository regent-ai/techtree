defmodule TechTreeWeb.RequireAgentSiwaHttpVerifyIntegrationTest do
  use TechTreeWeb.ConnCase, async: false

  import Ecto.Query

  alias TechTree.Agents
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Repo
  alias TechTreeWeb.TestSupport.SiwaIntegrationSupport, as: SiwaSupport

  setup_all do
    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    sidecar_port = SiwaSupport.available_port()

    start_supervised!(%{
      id: TechTreeWeb.TestSupport.SiwaSidecarState,
      start:
        {Agent, :start_link,
         [
           fn -> %{status: 200, last_request: nil} end,
           [name: TechTreeWeb.TestSupport.SiwaSidecarState]
         ]}
    })

    start_supervised!(
      {Bandit,
       plug: TechTreeWeb.TestSupport.SiwaSidecarStub, ip: {127, 0, 0, 1}, port: sidecar_port}
    )

    Application.put_env(:tech_tree, :siwa,
      internal_url: "http://127.0.0.1:#{sidecar_port}",
      skip_http_verify: false
    )

    on_exit(fn -> Application.put_env(:tech_tree, :siwa, original_siwa_cfg) end)

    :ok
  end

  setup do
    SiwaSupport.reset_sidecar_state()
    :ok
  end

  test "allows request when sidecar returns 200", %{conn: conn} do
    SiwaSupport.put_sidecar_status(200)

    wallet = SiwaSupport.random_eth_address()
    registry = SiwaSupport.random_eth_address()

    conn =
      conn
      |> SiwaSupport.with_siwa_headers(
        wallet: wallet,
        registry_address: registry,
        token_id: "101"
      )
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "SIWA integration",
        "parent_id" => 999_999,
        "notebook_source" => "print('ok')"
      })

    assert %{"error" => %{"code" => "parent_not_found"}} = json_response(conn, 422)

    assert Repo.exists?(
             from(a in AgentIdentity,
               where:
                 a.wallet_address == ^wallet and a.chain_id == 84_532 and
                   a.registry_address == ^registry
             )
           )

    assert %{
             "headers" => headers,
             "method" => "POST",
             "path" => "/v1/tree/nodes"
           } = SiwaSupport.sidecar_last_request()

    assert headers["x-agent-wallet-address"] == wallet
    assert headers["x-agent-chain-id"] == "84532"
    assert headers["x-agent-registry-address"] == registry
    assert headers["x-agent-token-id"] == "101"
  end

  test "denies request when sidecar returns 401", %{conn: conn} do
    SiwaSupport.put_sidecar_status(401)

    wallet = SiwaSupport.random_eth_address()
    telemetry_ref = SiwaSupport.attach_siwa_deny_handler()
    on_exit(fn -> :telemetry.detach(telemetry_ref) end)

    conn =
      conn
      |> SiwaSupport.with_siwa_headers(wallet: wallet, token_id: "202")
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "SIWA integration",
        "parent_id" => 999_999,
        "notebook_source" => "print('ok')"
      })

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)
    refute Repo.exists?(from(a in AgentIdentity, where: a.wallet_address == ^wallet))

    assert_receive {:siwa_deny,
                    %{reason: :sidecar_http_401, sidecar_status: 401, source: :sidecar_http}}
  end

  test "denies request when sidecar returns 422 and emits deny metadata", %{conn: conn} do
    SiwaSupport.put_sidecar_status(422)

    wallet = SiwaSupport.random_eth_address()
    telemetry_ref = SiwaSupport.attach_siwa_deny_handler()
    on_exit(fn -> :telemetry.detach(telemetry_ref) end)

    conn =
      conn
      |> SiwaSupport.with_siwa_headers(wallet: wallet, token_id: "303")
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "SIWA integration",
        "parent_id" => 999_999,
        "notebook_source" => "print('ok')"
      })

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)
    refute Repo.exists?(from(a in AgentIdentity, where: a.wallet_address == ^wallet))

    assert_receive {:siwa_deny,
                    %{reason: :sidecar_http_422, sidecar_status: 422, source: :sidecar_http}}
  end

  test "denies request without required agent headers and skips sidecar call", %{conn: conn} do
    telemetry_ref = SiwaSupport.attach_siwa_deny_handler()
    on_exit(fn -> :telemetry.detach(telemetry_ref) end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-agent-wallet-address", SiwaSupport.random_eth_address())
      |> put_req_header("x-agent-chain-id", "84532")
      |> put_req_header("x-agent-registry-address", SiwaSupport.random_eth_address())
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "SIWA missing headers",
        "parent_id" => 999_999,
        "notebook_source" => "print('ok')"
      })

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)

    assert %{
             "headers" => headers,
             "method" => "POST",
             "path" => "/v1/tree/nodes"
           } = SiwaSupport.sidecar_last_request()

    assert headers["x-agent-wallet-address"]
    assert headers["x-agent-registry-address"]

    assert_receive {:siwa_deny, %{reason: :missing_agent_headers, source: :request_headers}}
  end

  test "denies request when sidecar is unavailable and emits transport metadata", %{conn: conn} do
    telemetry_ref = SiwaSupport.attach_siwa_deny_handler()
    on_exit(fn -> :telemetry.detach(telemetry_ref) end)

    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])

    Application.put_env(:tech_tree, :siwa,
      internal_url: "http://127.0.0.1:1",
      skip_http_verify: false
    )

    on_exit(fn -> Application.put_env(:tech_tree, :siwa, original_siwa_cfg) end)

    conn =
      conn
      |> SiwaSupport.with_siwa_headers(token_id: "404")
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "SIWA sidecar down",
        "parent_id" => 999_999,
        "notebook_source" => "print('ok')"
      })

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)

    assert_receive {:siwa_deny, %{reason: :sidecar_request_failed, source: :sidecar_http}}
  end

  test "denies banned agent even when SIWA envelope is valid", %{conn: conn} do
    SiwaSupport.put_sidecar_status(200)

    wallet = SiwaSupport.random_eth_address()
    registry = SiwaSupport.random_eth_address()
    token_id = "808"

    Agents.upsert_verified_agent!(%{
      "chain_id" => "84532",
      "registry_address" => registry,
      "token_id" => token_id,
      "wallet_address" => wallet
    })

    {banned_count, _} =
      Repo.update_all(
        from(a in AgentIdentity,
          where:
            a.wallet_address == ^wallet and a.chain_id == 84_532 and
              a.registry_address == ^registry
        ),
        set: [status: "banned"]
      )

    assert banned_count == 1

    conn =
      conn
      |> SiwaSupport.with_siwa_headers(
        wallet: wallet,
        registry_address: registry,
        token_id: token_id
      )
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "SIWA banned",
        "parent_id" => 999_999,
        "notebook_source" => "print('ok')"
      })

    assert %{"error" => %{"code" => "agent_banned"}} = json_response(conn, 403)

    assert %AgentIdentity{status: "banned"} =
             Repo.get_by!(AgentIdentity,
               chain_id: 84_532,
               registry_address: registry,
               token_id: Decimal.new(token_id)
             )
  end

  test "denies banned agent when the request registry header only differs by case", %{conn: conn} do
    SiwaSupport.put_sidecar_status(200)

    wallet = SiwaSupport.random_eth_address()
    registry = SiwaSupport.random_eth_address()
    mixed_case_wallet = "0x" <> String.upcase(String.trim_leading(wallet, "0x"))
    mixed_case_registry = "0x" <> String.upcase(String.trim_leading(registry, "0x"))
    token_id = "909"

    Agents.upsert_verified_agent!(%{
      "chain_id" => "84532",
      "registry_address" => mixed_case_registry,
      "token_id" => token_id,
      "wallet_address" => mixed_case_wallet
    })

    {banned_count, _} =
      Repo.update_all(
        from(a in AgentIdentity,
          where:
            a.wallet_address == ^wallet and a.chain_id == 84_532 and
              a.registry_address == ^registry
        ),
        set: [status: "banned"]
      )

    assert banned_count == 1

    conn =
      conn
      |> SiwaSupport.with_siwa_headers(
        wallet: mixed_case_wallet,
        registry_address: mixed_case_registry,
        token_id: token_id
      )
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "SIWA banned mixed case",
        "parent_id" => 999_999,
        "notebook_source" => "print('ok')"
      })

    assert %{"error" => %{"code" => "agent_banned"}} = json_response(conn, 403)
  end
end
