defmodule TechTreeWeb.AgentSessionControllerTest do
  use TechTreeWeb.ConnCase, async: false

  alias TechTreeWeb.TestSupport.SiwaIntegrationSupport, as: SiwaSupport

  setup_all do
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

    {:ok, sidecar_url: "http://127.0.0.1:#{sidecar_port}"}
  end

  setup do
    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    Application.put_env(:tech_tree, :siwa, skip_http_verify: true)
    on_exit(fn -> Application.put_env(:tech_tree, :siwa, original_siwa_cfg) end)
    :ok
  end

  test "create, show, and delete keep the full verified agent identity in the local app session",
       %{
         conn: conn
       } do
    wallet = SiwaSupport.random_eth_address()
    registry = SiwaSupport.random_eth_address()
    token_id = "101"

    created_conn =
      conn
      |> init_test_session(%{})
      |> SiwaSupport.with_siwa_headers(
        wallet: wallet,
        registry_address: registry,
        token_id: token_id
      )
      |> post("/api/auth/agent/session", %{})

    created = json_response(created_conn, 200)

    assert created["ok"] == true
    assert created["session"]["audience"] == "techtree"
    assert created["session"]["wallet_address"] == wallet
    assert created["session"]["chain_id"] == "84532"
    assert created["session"]["registry_address"] == registry
    assert created["session"]["token_id"] == token_id
    assert is_binary(created["session"]["session_id"])

    show_conn =
      created_conn
      |> recycle()
      |> get("/api/auth/agent/session")

    shown = json_response(show_conn, 200)

    assert shown["ok"] == true
    assert shown["session"]["session_id"] == created["session"]["session_id"]
    assert shown["session"]["registry_address"] == registry
    assert shown["session"]["token_id"] == token_id

    delete_conn =
      show_conn
      |> recycle()
      |> delete("/api/auth/agent/session")

    assert %{"ok" => true} = json_response(delete_conn, 200)

    cleared_conn =
      delete_conn
      |> recycle()
      |> get("/api/auth/agent/session")

    assert %{"ok" => true, "session" => nil} = json_response(cleared_conn, 200)
  end

  test "shared verifier response can exchange into a local techtree session", %{
    conn: conn,
    sidecar_url: sidecar_url
  } do
    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    SiwaSupport.reset_sidecar_state()

    Application.put_env(:tech_tree, :siwa,
      internal_url: sidecar_url,
      skip_http_verify: false
    )

    on_exit(fn -> Application.put_env(:tech_tree, :siwa, original_siwa_cfg) end)

    wallet = SiwaSupport.random_eth_address()
    registry = SiwaSupport.random_eth_address()
    token_id = "202"

    conn =
      conn
      |> init_test_session(%{})
      |> SiwaSupport.with_siwa_headers(
        wallet: wallet,
        registry_address: registry,
        token_id: token_id
      )
      |> post("/api/auth/agent/session", %{})

    response = json_response(conn, 200)

    assert response["ok"] == true
    assert response["session"]["wallet_address"] == wallet
    assert response["session"]["registry_address"] == registry
    assert response["session"]["token_id"] == token_id

    assert %{"headers" => headers, "path" => "/api/auth/agent/session"} =
             SiwaSupport.sidecar_last_request()

    assert headers["x-agent-wallet-address"] == wallet
    assert headers["x-agent-registry-address"] == registry
    assert headers["x-agent-token-id"] == token_id
  end
end
