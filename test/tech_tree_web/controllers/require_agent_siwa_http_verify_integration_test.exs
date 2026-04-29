defmodule TechTreeWeb.RequireAgentSiwaHttpVerifyIntegrationTest do
  use TechTreeWeb.ConnCase, async: false

  import Ecto.Query

  alias TechTree.Agents
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Repo
  alias TechTreeWeb.TestSupport.SiwaIntegrationSupport, as: SiwaSupport

  setup_all do
    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    Application.put_env(:tech_tree, :siwa, siwa_cfg)

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
      |> put_req_header("content-type", "application/json")
      |> post(
        "/v1/tree/nodes",
        Jason.encode!(%{
          "seed" => "ML",
          "kind" => "hypothesis",
          "title" => "SIWA integration",
          "parent_id" => 999_999,
          "notebook_source" => "print('ok')"
        })
      )

    assert %{"error" => %{"code" => "parent_not_found"}} = json_response(conn, 422)

    assert Repo.exists?(
             from(a in AgentIdentity,
               where:
                 a.wallet_address == ^wallet and a.chain_id == 84_532 and
                   a.registry_address == ^registry
             )
           )

    assert %{
             "kind" => "http_verify_request",
             "headers" => headers,
             "method" => "POST",
             "path" => "/v1/tree/nodes",
             "body" => raw_body
           } = SiwaSupport.sidecar_last_request()

    assert headers["x-agent-wallet-address"] == wallet
    assert headers["x-agent-chain-id"] == "84532"
    assert headers["x-agent-registry-address"] == registry
    assert headers["x-agent-token-id"] == "101"
    assert raw_body =~ "SIWA integration"

    assert %{
             "x-sidecar-key-id" => "sidecar-internal-v1",
             "x-sidecar-timestamp" => timestamp,
             "x-sidecar-signature" => "sha256=" <> signature
           } = SiwaSupport.sidecar_last_trusted_headers()

    assert {_timestamp, ""} = Integer.parse(timestamp)
    assert byte_size(signature) == 64
  end

  test "protects runtime write routes with agent SIWA", %{conn: conn} do
    SiwaSupport.put_sidecar_status(200)

    wallet = SiwaSupport.random_eth_address()
    registry = SiwaSupport.random_eth_address()

    conn =
      conn
      |> SiwaSupport.with_siwa_headers(
        wallet: wallet,
        registry_address: registry,
        token_id: "111"
      )
      |> put_req_header("content-type", "application/json")
      |> post("/v1/agent/runtime/publish/submit", Jason.encode!(%{}))

    assert %{"error" => %{"code" => "publish_submit_failed"}} = json_response(conn, 422)

    assert Repo.exists?(
             from(a in AgentIdentity,
               where:
                 a.wallet_address == ^wallet and a.chain_id == 84_532 and
                   a.registry_address == ^registry
             )
           )

    assert %{
             "kind" => "http_verify_request",
             "headers" => headers,
             "method" => "POST",
             "path" => "/v1/agent/runtime/publish/submit",
             "body" => "{}"
           } = SiwaSupport.sidecar_last_request()

    assert headers["x-agent-wallet-address"] == wallet
    assert headers["x-agent-chain-id"] == "84532"
    assert headers["x-agent-registry-address"] == registry
    assert headers["x-agent-token-id"] == "111"
  end

  test "shared SIWA verifier accepts a fully signed write request", %{conn: conn} do
    with_strict_shared_siwa_client()

    body =
      Jason.encode!(%{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "Strict SIWA integration",
        "parent_id" => 999_999,
        "notebook_source" => "print('ok')"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> SiwaSupport.with_shared_siwa_signed_request("POST", "/v1/tree/nodes", body,
        token_id: "515"
      )
      |> post("/v1/tree/nodes", body)

    assert %{"error" => %{"code" => "parent_not_found"}} = json_response(conn, 422)

    assert Repo.exists?(
             from(a in AgentIdentity,
               where: a.token_id == ^Decimal.new("515") and a.chain_id == 84_532
             )
           )
  end

  test "shared SIWA verifier denies missing covered components", %{conn: conn} do
    with_strict_shared_siwa_client()

    body = Jason.encode!(%{"seed" => "ML", "title" => "Missing covered component"})

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> SiwaSupport.with_shared_siwa_signed_request("POST", "/v1/tree/nodes", body,
        token_id: "616"
      )
      |> remove_signature_component("content-digest")
      |> post("/v1/tree/nodes", body)

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)
    refute Repo.exists?(from(a in AgentIdentity, where: a.token_id == ^Decimal.new("616")))
  end

  test "shared SIWA verifier denies body digest mismatch", %{conn: conn} do
    with_strict_shared_siwa_client()

    signed_body = Jason.encode!(%{"seed" => "ML", "title" => "Signed body"})
    posted_body = Jason.encode!(%{"seed" => "ML", "title" => "Changed body"})

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> SiwaSupport.with_shared_siwa_signed_request("POST", "/v1/tree/nodes", signed_body,
        token_id: "717"
      )
      |> post("/v1/tree/nodes", posted_body)

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)
    refute Repo.exists?(from(a in AgentIdentity, where: a.token_id == ^Decimal.new("717")))
  end

  test "shared SIWA verifier denies mutated wallet registry and token headers" do
    with_strict_shared_siwa_client()

    for {header, value, token_id} <- [
          {"x-agent-wallet-address", SiwaSupport.random_eth_address(), "818"},
          {"x-agent-registry-address", SiwaSupport.random_eth_address(), "819"},
          {"x-agent-token-id", "999999", "820"}
        ] do
      body = Jason.encode!(%{"seed" => "ML", "title" => "Mutated #{header}"})

      denied_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> SiwaSupport.with_shared_siwa_signed_request("POST", "/v1/tree/nodes", body,
          token_id: token_id
        )
        |> put_req_header(header, value)
        |> post("/v1/tree/nodes", body)

      assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(denied_conn, 401)
      refute Repo.exists?(from(a in AgentIdentity, where: a.token_id == ^Decimal.new(token_id)))
    end
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

  test "lets the sidecar decide when the signed receipt no longer matches the request headers", %{
    conn: conn
  } do
    SiwaSupport.put_sidecar_status(401)

    telemetry_ref = SiwaSupport.attach_siwa_deny_handler()
    on_exit(fn -> :telemetry.detach(telemetry_ref) end)

    wallet = SiwaSupport.random_eth_address()
    registry = SiwaSupport.random_eth_address()

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-agent-wallet-address", wallet)
      |> put_req_header("x-agent-chain-id", "84532")
      |> put_req_header("x-agent-registry-address", registry)
      |> put_req_header("x-agent-token-id", "202")
      |> put_req_header(
        "x-siwa-receipt",
        receipt_token(wallet, "84532", registry, "101", "techtree")
      )
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "SIWA missing headers",
        "parent_id" => 999_999,
        "notebook_source" => "print('ok')"
      })

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)

    assert %{
             "kind" => "http_verify_request",
             "headers" => headers,
             "method" => "POST",
             "path" => "/v1/tree/nodes"
           } = SiwaSupport.sidecar_last_request()

    assert headers["x-agent-wallet-address"] == wallet
    assert headers["x-agent-registry-address"] == registry

    assert_receive {:siwa_deny,
                    %{reason: :sidecar_http_401, sidecar_status: 401, source: :sidecar_http}}
  end

  test "denies request when sidecar is unavailable and emits transport metadata", %{conn: conn} do
    telemetry_ref = SiwaSupport.attach_siwa_deny_handler()
    on_exit(fn -> :telemetry.detach(telemetry_ref) end)

    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])

    Application.put_env(:tech_tree, :siwa,
      internal_url: "http://127.0.0.1:1",
      shared_secret: Keyword.fetch!(original_siwa_cfg, :shared_secret)
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

    assert %{"error" => %{"code" => "siwa_unavailable"}} = json_response(conn, 503)

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

  defp receipt_token(wallet, chain_id, registry, token_id, audience) do
    secret =
      Application.get_env(:tech_tree, :siwa, [])
      |> Keyword.fetch!(:shared_secret)

    now_ms = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    payload =
      %{
        "typ" => "siwa_receipt",
        "jti" => Ecto.UUID.generate(),
        "sub" => wallet,
        "aud" => audience,
        "verified" => "onchain",
        "iat" => now_ms,
        "exp" => now_ms + 600_000,
        "chain_id" => String.to_integer(chain_id),
        "nonce" => "nonce-#{System.unique_integer([:positive])}",
        "key_id" => wallet,
        "registry_address" => registry,
        "token_id" => token_id
      }
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    signature =
      :crypto.mac(:hmac, :sha256, secret, payload)
      |> Base.url_encode64(padding: false)

    "#{payload}.#{signature}"
  end

  defp with_strict_shared_siwa_client do
    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])

    Application.put_env(
      :tech_tree,
      :siwa,
      Keyword.put(original_siwa_cfg, :client, TechTreeWeb.TestSupport.StrictSiwaSidecarClient)
    )

    on_exit(fn -> Application.put_env(:tech_tree, :siwa, original_siwa_cfg) end)
  end

  defp remove_signature_component(conn, component) do
    [signature_input] = get_req_header(conn, "signature-input")

    put_req_header(
      conn,
      "signature-input",
      String.replace(signature_input, ~s( "#{component}"), "")
    )
  end
end
