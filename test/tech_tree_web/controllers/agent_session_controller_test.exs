defmodule TechTreeWeb.AgentSessionControllerTest do
  use TechTreeWeb.ConnCase, async: false

  alias TechTreeWeb.TestSupport.SiwaIntegrationSupport, as: SiwaSupport

  defmodule FakeSiwaSidecarClient do
    @behaviour TechTree.SiwaSidecarClient

    @impl true
    def verify_http_request(conn, normalized_headers) do
      :tech_tree
      |> Application.get_env(:siwa, [])
      |> Keyword.fetch!(:test_pid)
      |> send(
        {:fake_siwa_verified, conn.request_path, normalized_headers, conn.assigns[:raw_body]}
      )

      {:ok,
       %{
         status: 200,
         body: %{
           "ok" => true,
           "code" => "http_envelope_valid",
           "data" => %{
             "verified" => true,
             "walletAddress" => normalized_headers["x-agent-wallet-address"],
             "chainId" => String.to_integer(normalized_headers["x-agent-chain-id"]),
             "keyId" => normalized_headers["x-key-id"],
             "receiptExpiresAt" => "2026-04-28T00:00:00.000Z",
             "requiredHeaders" => ["x-siwa-receipt"],
             "requiredCoveredComponents" => ["@method", "@path", "x-siwa-receipt"],
             "coveredComponents" => ["@method", "@path", "x-siwa-receipt"]
           }
         }
       }}
    end
  end

  setup do
    SiwaSupport.reset_sidecar_state()
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

  test "shared verifier response can exchange into a local techtree session", %{conn: conn} do
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

    assert %{
             "kind" => "http_verify_request",
             "headers" => headers,
             "method" => "POST",
             "path" => "/api/auth/agent/session"
           } =
             SiwaSupport.sidecar_last_request()

    assert headers["x-agent-wallet-address"] == wallet
    assert headers["x-agent-registry-address"] == registry
    assert headers["x-agent-token-id"] == token_id

    assert %{
             "x-sidecar-key-id" => "sidecar-internal-v1",
             "x-sidecar-timestamp" => timestamp,
             "x-sidecar-signature" => "sha256=" <> signature
           } = SiwaSupport.sidecar_last_trusted_headers()

    assert {_timestamp, ""} = Integer.parse(timestamp)
    assert byte_size(signature) == 64
  end

  test "session creation can use the configured SIWA client behavior", %{conn: conn} do
    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])

    Application.put_env(
      :tech_tree,
      :siwa,
      original_siwa_cfg
      |> Keyword.put(:client, FakeSiwaSidecarClient)
      |> Keyword.put(:test_pid, self())
    )

    on_exit(fn -> Application.put_env(:tech_tree, :siwa, original_siwa_cfg) end)

    wallet = SiwaSupport.random_eth_address()
    registry = SiwaSupport.random_eth_address()

    conn =
      conn
      |> init_test_session(%{})
      |> SiwaSupport.with_siwa_headers(
        wallet: wallet,
        registry_address: registry,
        token_id: "212"
      )
      |> put_req_header("content-type", "application/json")
      |> post("/api/auth/agent/session", Jason.encode!(%{}))

    response = json_response(conn, 200)

    assert response["ok"] == true
    assert response["session"]["wallet_address"] == wallet
    assert response["session"]["registry_address"] == registry
    assert response["session"]["token_id"] == "212"

    assert_receive {:fake_siwa_verified, "/api/auth/agent/session", headers, raw_body}
    assert headers["x-agent-wallet-address"] == wallet
    assert headers["x-agent-registry-address"] == registry
    assert raw_body == "{}"
    assert SiwaSupport.sidecar_last_request() == nil
  end

  test "session creation rejects a receipt minted for another app", %{conn: conn} do
    SiwaSupport.put_sidecar_status(401)

    wallet = SiwaSupport.random_eth_address()
    registry = SiwaSupport.random_eth_address()

    conn =
      conn
      |> init_test_session(%{})
      |> SiwaSupport.with_siwa_headers(
        wallet: wallet,
        registry_address: registry,
        token_id: "303",
        receipt_audience: "platform"
      )
      |> post("/api/auth/agent/session", %{})

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)

    assert %{
             "kind" => "http_verify_request",
             "headers" => headers,
             "method" => "POST",
             "path" => "/api/auth/agent/session"
           } = SiwaSupport.sidecar_last_request()

    assert headers["x-siwa-receipt"]
  end
end
