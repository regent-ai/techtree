defmodule TechTreeWeb.RequireAgentSiwaIntegrationTest do
  use TechTreeWeb.ConnCase, async: false

  import Ecto.Query

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Repo

  setup_all do
    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    sidecar_port = available_port()

    start_supervised!(%{
      id: TechTreeWeb.TestSupport.SiwaSidecarState,
      start:
        {Agent, :start_link,
         [fn -> %{status: 200, last_request: nil} end, [name: TechTreeWeb.TestSupport.SiwaSidecarState]]}
    })

    start_supervised!(
      {Bandit,
       plug: TechTreeWeb.TestSupport.SiwaSidecarStub,
       ip: {127, 0, 0, 1},
       port: sidecar_port}
    )

    Application.put_env(:tech_tree, :siwa,
      internal_url: "http://127.0.0.1:#{sidecar_port}",
      shared_secret: "integration-secret",
      skip_http_verify: false
    )

    on_exit(fn -> Application.put_env(:tech_tree, :siwa, original_siwa_cfg) end)

    :ok
  end

  setup do
    Process.put(:tech_tree_disable_rate_limits, true)

    on_exit(fn ->
      Process.delete(:tech_tree_disable_rate_limits)
    end)

    :ok
  end

  test "allows request when sidecar returns 200", %{conn: conn} do
    put_sidecar_status(200)

    wallet = random_eth_address()
    registry = random_eth_address()

    conn =
      conn
      |> with_siwa_headers(wallet: wallet, registry_address: registry, token_id: "101")
      |> post("/v1/agent/nodes", %{
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
                 a.wallet_address == ^wallet and a.chain_id == 8453 and
                   a.registry_address == ^registry
             )
           )

    assert %{
             "kind" => "http_verify_request",
             "headers" => headers,
             "method" => "POST",
             "path" => "/v1/agent/nodes"
           } = sidecar_last_request()

    assert headers["x-agent-wallet-address"] == wallet
    assert headers["x-agent-chain-id"] == "8453"
    assert headers["x-agent-registry-address"] == registry
    assert headers["x-agent-token-id"] == "101"
  end

  test "denies request when sidecar returns 401", %{conn: conn} do
    put_sidecar_status(401)

    wallet = random_eth_address()
    telemetry_ref = attach_siwa_deny_handler()
    on_exit(fn -> :telemetry.detach(telemetry_ref) end)

    conn =
      conn
      |> with_siwa_headers(wallet: wallet, token_id: "202")
      |> post("/v1/agent/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "SIWA integration",
        "parent_id" => 999_999,
        "notebook_source" => "print('ok')"
      })

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)
    refute Repo.exists?(from(a in AgentIdentity, where: a.wallet_address == ^wallet))

    assert_receive {:siwa_deny, %{reason: :sidecar_http_401, sidecar_status: 401, source: :sidecar_http}}
  end

  test "denies request when sidecar returns 422 and emits deny metadata", %{conn: conn} do
    put_sidecar_status(422)

    wallet = random_eth_address()
    telemetry_ref = attach_siwa_deny_handler()
    on_exit(fn -> :telemetry.detach(telemetry_ref) end)

    conn =
      conn
      |> with_siwa_headers(wallet: wallet, token_id: "303")
      |> post("/v1/agent/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "SIWA integration",
        "parent_id" => 999_999,
        "notebook_source" => "print('ok')"
      })

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)
    refute Repo.exists?(from(a in AgentIdentity, where: a.wallet_address == ^wallet))

    assert_receive {:siwa_deny, %{reason: :sidecar_http_422, sidecar_status: 422, source: :sidecar_http}}
  end

  defp with_siwa_headers(conn, opts) do
    unique = System.unique_integer([:positive])
    wallet = Keyword.get(opts, :wallet, random_eth_address())
    registry = Keyword.get(opts, :registry_address, random_eth_address())
    chain_id = Keyword.get(opts, :chain_id, "8453")
    token_id = Keyword.get(opts, :token_id, Integer.to_string(unique))

    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-agent-wallet-address", wallet)
    |> put_req_header("x-agent-chain-id", chain_id)
    |> put_req_header("x-agent-registry-address", registry)
    |> put_req_header("x-agent-token-id", token_id)
  end

  defp attach_siwa_deny_handler do
    parent = self()
    telemetry_ref = "siwa-deny-#{System.unique_integer([:positive, :monotonic])}"

    :ok =
      :telemetry.attach(
        telemetry_ref,
        [:tech_tree, :agent, :siwa, :deny],
        fn _event, _measurements, metadata, _config ->
          send(parent, {:siwa_deny, metadata})
        end,
        nil
      )

    telemetry_ref
  end

  defp put_sidecar_status(status) do
    Agent.update(TechTreeWeb.TestSupport.SiwaSidecarState, fn state ->
      Map.put(normalize_stub_state(state), :status, status)
    end)
  end

  defp sidecar_last_request do
    Agent.get(TechTreeWeb.TestSupport.SiwaSidecarState, fn state ->
      normalize_stub_state(state).last_request
    end)
  end

  defp normalize_stub_state(state) when is_map(state), do: Map.merge(%{status: 200, last_request: nil}, state)
  defp normalize_stub_state(status) when is_integer(status), do: %{status: status, last_request: nil}

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end

  defp available_port do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
