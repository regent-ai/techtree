defmodule TechTreeWeb.RequireAgentSiwaEndToEndIntegrationTest do
  use TechTreeWeb.ConnCase, async: false

  import Ecto.Query

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
      shared_secret: "integration-secret",
      skip_http_verify: false
    )

    on_exit(fn -> Application.put_env(:tech_tree, :siwa, original_siwa_cfg) end)

    :ok
  end

  setup do
    SiwaSupport.reset_sidecar_state()
    :ok
  end

  test "full SIWA flow nonce -> sign -> verify -> authenticated request", %{conn: conn} do
    SiwaSupport.with_external_siwa_sidecar(fn sidecar_url, shared_secret ->
      original_siwa_cfg = SiwaSupport.configure_siwa_sidecar!(sidecar_url, shared_secret)
      on_exit(fn -> SiwaSupport.restore_siwa_config!(original_siwa_cfg) end)

      private_key = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
      wallet = SiwaSupport.cast_wallet_address!(private_key)
      wallet_key_id = String.downcase(wallet)
      registry = SiwaSupport.random_eth_address()
      token_id = "1901"

      nonce_conn =
        post(conn, "/v1/agent/siwa/nonce", %{
          "walletAddress" => wallet,
          "chainId" => 11_155_111,
          "audience" => "techtree"
        })

      assert %{
               "ok" => true,
               "code" => "nonce_issued",
               "data" => %{"nonce" => nonce}
             } = json_response(nonce_conn, 200)

      message = SiwaSupport.siwe_message(wallet, nonce, 11_155_111)
      signature = SiwaSupport.cast_wallet_sign!(private_key, message)

      verify_conn =
        post(conn, "/v1/agent/siwa/verify", %{
          "walletAddress" => wallet,
          "chainId" => 11_155_111,
          "nonce" => nonce,
          "message" => message,
          "signature" => signature,
          "registryAddress" => registry,
          "tokenId" => token_id
        })

      assert %{
               "ok" => true,
               "code" => "siwa_verified",
               "data" => %{"receipt" => receipt}
             } = json_response(verify_conn, 200)

      request_path = "/v1/tree/nodes"
      request_method = "POST"
      timestamp = System.os_time(:second)

      {signature_input, signing_message} =
        SiwaSupport.signed_http_envelope_payload(%{
          method: request_method,
          path: request_path,
          timestamp: timestamp,
          key_id: wallet_key_id,
          receipt: receipt,
          wallet: wallet,
          chain_id: "11155111",
          registry: registry,
          token_id: token_id
        })

      request_signature = SiwaSupport.cast_wallet_sign!(private_key, signing_message)

      authed_conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-siwa-receipt", receipt)
        |> put_req_header("x-key-id", wallet_key_id)
        |> put_req_header("x-timestamp", Integer.to_string(timestamp))
        |> put_req_header("signature-input", signature_input)
        |> put_req_header("signature", request_signature)
        |> SiwaSupport.with_siwa_headers(
          wallet: wallet,
          chain_id: "11155111",
          registry_address: registry,
          token_id: token_id
        )
        |> post(request_path, %{
          "seed" => "ML",
          "kind" => "hypothesis",
          "title" => "SIWA full flow",
          "parent_id" => 999_999,
          "notebook_source" => "print('ok')"
        })

      assert %{"error" => %{"code" => "parent_not_found"}} = json_response(authed_conn, 422)

      assert Repo.exists?(
               from(a in AgentIdentity,
                 where:
                   a.wallet_address == ^wallet and a.chain_id == 11_155_111 and
                     a.registry_address == ^registry
               )
             )
    end)
  end

  test "verify endpoint rejects invalid signature", %{conn: conn} do
    SiwaSupport.with_external_siwa_sidecar(fn sidecar_url, shared_secret ->
      original_siwa_cfg = SiwaSupport.configure_siwa_sidecar!(sidecar_url, shared_secret)
      on_exit(fn -> SiwaSupport.restore_siwa_config!(original_siwa_cfg) end)

      private_key = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
      wallet = SiwaSupport.cast_wallet_address!(private_key)

      nonce_conn =
        post(conn, "/v1/agent/siwa/nonce", %{
          "walletAddress" => wallet,
          "chainId" => 11_155_111
        })

      assert %{"ok" => true, "data" => %{"nonce" => nonce}} = json_response(nonce_conn, 200)

      message = SiwaSupport.siwe_message(wallet, nonce, 11_155_111)
      signature = SiwaSupport.cast_wallet_sign!(private_key, message)

      <<prefix::binary-size(4), _rest::binary>> = signature
      invalid_signature = prefix <> String.duplicate("0", byte_size(signature) - 4)

      verify_conn =
        post(conn, "/v1/agent/siwa/verify", %{
          "walletAddress" => wallet,
          "chainId" => 11_155_111,
          "nonce" => nonce,
          "message" => message,
          "signature" => invalid_signature
        })

      assert verify_conn.status in [401, 422]

      assert %{"ok" => false, "code" => "signature_invalid"} =
               json_response(verify_conn, verify_conn.status)
    end)
  end

  test "verify endpoint rejects expired nonce", %{conn: conn} do
    SiwaSupport.with_external_siwa_sidecar(
      fn sidecar_url, shared_secret ->
        original_siwa_cfg = SiwaSupport.configure_siwa_sidecar!(sidecar_url, shared_secret)
        on_exit(fn -> SiwaSupport.restore_siwa_config!(original_siwa_cfg) end)

        private_key = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
        wallet = SiwaSupport.cast_wallet_address!(private_key)

        nonce_conn =
          post(conn, "/v1/agent/siwa/nonce", %{
            "walletAddress" => wallet,
            "chainId" => 11_155_111
          })

        assert %{
                 "ok" => true,
                 "data" => %{"nonce" => nonce, "expiresAt" => expires_at}
               } = json_response(nonce_conn, 200)

        SiwaSupport.wait_until_expired!(expires_at)

        message = SiwaSupport.siwe_message(wallet, nonce, 11_155_111)
        signature = SiwaSupport.cast_wallet_sign!(private_key, message)

        verify_conn =
          post(conn, "/v1/agent/siwa/verify", %{
            "walletAddress" => wallet,
            "chainId" => 11_155_111,
            "nonce" => nonce,
            "message" => message,
            "signature" => signature
          })

        assert verify_conn.status in [401, 422]

        assert %{"ok" => false, "code" => "nonce_expired"} =
                 json_response(verify_conn, verify_conn.status)
      end,
      nonce_ttl_seconds: 1
    )
  end
end
