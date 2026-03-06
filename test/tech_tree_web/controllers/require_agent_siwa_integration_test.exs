defmodule TechTreeWeb.RequireAgentSiwaIntegrationTest do
  use TechTreeWeb.ConnCase, async: false

  import Ecto.Query

  alias TechTree.Agents
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Repo

  setup_all do
    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    sidecar_port = available_port()

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
    Process.put(:tech_tree_disable_rate_limits, true)
    reset_sidecar_state()

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
                 a.wallet_address == ^wallet and a.chain_id == 8453 and
                   a.registry_address == ^registry
             )
           )

    assert %{
             "kind" => "http_verify_request",
             "headers" => headers,
             "method" => "POST",
             "path" => "/v1/tree/nodes"
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
    put_sidecar_status(422)

    wallet = random_eth_address()
    telemetry_ref = attach_siwa_deny_handler()
    on_exit(fn -> :telemetry.detach(telemetry_ref) end)

    conn =
      conn
      |> with_siwa_headers(wallet: wallet, token_id: "303")
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
    telemetry_ref = attach_siwa_deny_handler()
    on_exit(fn -> :telemetry.detach(telemetry_ref) end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-agent-wallet-address", random_eth_address())
      |> put_req_header("x-agent-chain-id", "8453")
      |> put_req_header("x-agent-registry-address", random_eth_address())
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "SIWA missing headers",
        "parent_id" => 999_999,
        "notebook_source" => "print('ok')"
      })

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)
    assert sidecar_last_request() == nil

    assert_receive {:siwa_deny,
                    %{reason: :missing_agent_headers, source: :request_headers}}
  end

  test "denies request when sidecar is unavailable and emits transport metadata", %{conn: conn} do
    telemetry_ref = attach_siwa_deny_handler()
    on_exit(fn -> :telemetry.detach(telemetry_ref) end)

    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])

    Application.put_env(:tech_tree, :siwa,
      internal_url: "http://127.0.0.1:1",
      shared_secret: "integration-secret",
      skip_http_verify: false
    )

    on_exit(fn -> Application.put_env(:tech_tree, :siwa, original_siwa_cfg) end)

    conn =
      conn
      |> with_siwa_headers(token_id: "404")
      |> post("/v1/tree/nodes", %{
        "seed" => "ML",
        "kind" => "hypothesis",
        "title" => "SIWA sidecar down",
        "parent_id" => 999_999,
        "notebook_source" => "print('ok')"
      })

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)

    assert_receive {:siwa_deny,
                    %{reason: :sidecar_request_failed, source: :sidecar_http}}
  end

  test "denies banned agent even when SIWA envelope is valid", %{conn: conn} do
    put_sidecar_status(200)

    wallet = random_eth_address()
    registry = random_eth_address()
    token_id = "808"

    Agents.upsert_verified_agent!(%{
      "chain_id" => "8453",
      "registry_address" => registry,
      "token_id" => token_id,
      "wallet_address" => wallet
    })

    {banned_count, _} =
      Repo.update_all(
        from(a in AgentIdentity,
          where:
            a.wallet_address == ^wallet and a.chain_id == 8453 and a.registry_address == ^registry
        ),
        set: [status: "banned"]
      )

    assert banned_count == 1

    conn =
      conn
      |> with_siwa_headers(wallet: wallet, registry_address: registry, token_id: token_id)
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
               chain_id: 8453,
               registry_address: registry,
               token_id: Decimal.new(token_id)
             )
  end

  test "full SIWA flow nonce -> sign -> verify -> authenticated request", %{conn: conn} do
    with_external_siwa_sidecar(fn sidecar_url, shared_secret ->
      configure_siwa_sidecar!(sidecar_url, shared_secret)

      private_key = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
      wallet = cast_wallet_address!(private_key)
      wallet_key_id = String.downcase(wallet)
      registry = random_eth_address()
      token_id = "1901"

      nonce_conn =
        post(conn, "/v1/agent/siwa/nonce", %{
          "walletAddress" => wallet,
          "chainId" => 8453,
          "audience" => "techtree"
        })

      assert %{
               "ok" => true,
               "code" => "nonce_issued",
               "data" => %{"nonce" => nonce}
             } = json_response(nonce_conn, 200)

      message = siwe_message(wallet, nonce, 8453)
      signature = cast_wallet_sign!(private_key, message)

      verify_conn =
        post(conn, "/v1/agent/siwa/verify", %{
          "walletAddress" => wallet,
          "chainId" => 8453,
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
        signed_http_envelope_payload(%{
          method: request_method,
          path: request_path,
          timestamp: timestamp,
          key_id: wallet_key_id,
          receipt: receipt,
          wallet: wallet,
          chain_id: "8453",
          registry: registry,
          token_id: token_id
        })

      request_signature = cast_wallet_sign!(private_key, signing_message)

      authed_conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-siwa-receipt", receipt)
        |> put_req_header("x-key-id", wallet_key_id)
        |> put_req_header("x-timestamp", Integer.to_string(timestamp))
        |> put_req_header("signature-input", signature_input)
        |> put_req_header("signature", request_signature)
        |> with_siwa_headers(
          wallet: wallet,
          chain_id: "8453",
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
                   a.wallet_address == ^wallet and a.chain_id == 8453 and
                     a.registry_address == ^registry
               )
             )
    end)
  end

  test "verify endpoint rejects invalid signature", %{conn: conn} do
    with_external_siwa_sidecar(fn sidecar_url, shared_secret ->
      configure_siwa_sidecar!(sidecar_url, shared_secret)

      private_key = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
      wallet = cast_wallet_address!(private_key)

      nonce_conn =
        post(conn, "/v1/agent/siwa/nonce", %{
          "walletAddress" => wallet,
          "chainId" => 8453
        })

      assert %{"ok" => true, "data" => %{"nonce" => nonce}} = json_response(nonce_conn, 200)

      message = siwe_message(wallet, nonce, 8453)
      signature = cast_wallet_sign!(private_key, message)

      <<prefix::binary-size(4), _rest::binary>> = signature
      invalid_signature = prefix <> String.duplicate("0", byte_size(signature) - 4)

      verify_conn =
        post(conn, "/v1/agent/siwa/verify", %{
          "walletAddress" => wallet,
          "chainId" => 8453,
          "nonce" => nonce,
          "message" => message,
          "signature" => invalid_signature
        })

      assert verify_conn.status in [401, 422]
      assert %{"ok" => false, "code" => "signature_invalid"} = json_response(verify_conn, verify_conn.status)
    end)
  end

  test "verify endpoint rejects expired nonce", %{conn: conn} do
    with_external_siwa_sidecar(
      fn sidecar_url, shared_secret ->
        configure_siwa_sidecar!(sidecar_url, shared_secret)

        private_key = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
        wallet = cast_wallet_address!(private_key)

        nonce_conn =
          post(conn, "/v1/agent/siwa/nonce", %{
            "walletAddress" => wallet,
            "chainId" => 8453
          })

        assert %{
                 "ok" => true,
                 "data" => %{"nonce" => nonce, "expiresAt" => expires_at}
               } = json_response(nonce_conn, 200)

        wait_until_expired!(expires_at)

        message = siwe_message(wallet, nonce, 8453)
        signature = cast_wallet_sign!(private_key, message)

        verify_conn =
          post(conn, "/v1/agent/siwa/verify", %{
            "walletAddress" => wallet,
            "chainId" => 8453,
            "nonce" => nonce,
            "message" => message,
            "signature" => signature
          })

        assert verify_conn.status in [401, 422]
        assert %{"ok" => false, "code" => "nonce_expired"} = json_response(verify_conn, verify_conn.status)
      end,
      nonce_ttl_seconds: 1
    )
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

  defp reset_sidecar_state do
    Agent.update(TechTreeWeb.TestSupport.SiwaSidecarState, fn _state ->
      %{status: 200, last_request: nil}
    end)
  end

  defp sidecar_last_request do
    Agent.get(TechTreeWeb.TestSupport.SiwaSidecarState, fn state ->
      normalize_stub_state(state).last_request
    end)
  end

  defp normalize_stub_state(state) when is_map(state),
    do: Map.merge(%{status: 200, last_request: nil}, state)

  defp normalize_stub_state(status) when is_integer(status),
    do: %{status: status, last_request: nil}

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

  defp with_external_siwa_sidecar(fun, opts \\ []) do
    node_executable =
      System.find_executable("node") ||
        raise ExUnit.SkipTest, "node executable is required for SIWA integration tests"

    _cast_executable =
      System.find_executable("cast") ||
        raise ExUnit.SkipTest, "cast executable is required for SIWA integration tests"

    sidecar_port = available_port()
    sidecar_url = "http://127.0.0.1:#{sidecar_port}"
    shared_secret = "siwa-real-secret-#{System.unique_integer([:positive])}"

    sidecar = start_external_siwa_sidecar!(node_executable, sidecar_port, shared_secret, opts)
    wait_for_sidecar!(sidecar_url)

    try do
      fun.(sidecar_url, shared_secret)
    after
      stop_external_siwa_sidecar(sidecar)
    end
  end

  defp start_external_siwa_sidecar!(node_executable, sidecar_port, shared_secret, opts) do
    server_path = Path.join(File.cwd!(), "services/siwa-sidecar/dist/server.js")

    unless File.exists?(server_path) do
      raise ExUnit.AssertionError, "missing SIWA sidecar dist build at #{server_path}"
    end

    base_env = [
      {"SIWA_PORT", Integer.to_string(sidecar_port)},
      {"SIWA_HMAC_SECRET", shared_secret},
      {"SIWA_RECEIPT_SECRET", shared_secret}
    ]

    optional_env =
      case Keyword.get(opts, :nonce_ttl_seconds) do
        value when is_integer(value) and value > 0 ->
          [{"SIWA_NONCE_TTL_SECONDS", Integer.to_string(value)}]

        _ ->
          []
      end

    env =
      (base_env ++ optional_env)
      |> Enum.map(fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)

    Port.open(
      {:spawn_executable, String.to_charlist(node_executable)},
      [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        args: [String.to_charlist(server_path)],
        env: env
      ]
    )
  end

  defp stop_external_siwa_sidecar(port) when is_port(port) do
    Port.close(port)
    :ok
  rescue
    _ -> :ok
  end

  defp wait_for_sidecar!(sidecar_url, attempts \\ 40)

  defp wait_for_sidecar!(_sidecar_url, 0) do
    raise ExUnit.AssertionError, "timed out waiting for SIWA sidecar to start"
  end

  defp wait_for_sidecar!(sidecar_url, attempts) do
    case Req.post(
           url: "#{sidecar_url}/v1/nonce",
           json: %{
             "kind" => "nonce_request",
             "walletAddress" => random_eth_address(),
             "chainId" => 8453,
             "audience" => "techtree"
           },
           receive_timeout: 300,
           connect_options: [timeout: 300]
         ) do
      {:ok, %{status: 200}} ->
        :ok

      _ ->
        receive do
        after
          100 -> wait_for_sidecar!(sidecar_url, attempts - 1)
        end
    end
  end

  defp configure_siwa_sidecar!(sidecar_url, shared_secret) do
    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])

    Application.put_env(:tech_tree, :siwa,
      internal_url: sidecar_url,
      shared_secret: shared_secret,
      skip_http_verify: false
    )

    on_exit(fn -> Application.put_env(:tech_tree, :siwa, original_siwa_cfg) end)
  end

  defp cast_wallet_address!(private_key) do
    {output, 0} =
      System.cmd("cast", ["wallet", "address", "--private-key", private_key], stderr_to_stdout: true)

    String.trim(output)
  end

  defp cast_wallet_sign!(private_key, message) do
    {output, 0} =
      System.cmd("cast", ["wallet", "sign", "--private-key", private_key, message], stderr_to_stdout: true)

    String.trim(output)
  end

  defp siwe_message(wallet, nonce, chain_id) do
    issued_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    [
      "techtree.local wants you to sign in with your Ethereum account:",
      wallet,
      "",
      "Sign in to TechTree SIWA integration tests.",
      "",
      "URI: https://techtree.local/login",
      "Version: 1",
      "Chain ID: #{chain_id}",
      "Nonce: #{nonce}",
      "Issued At: #{issued_at}"
    ]
    |> Enum.join("\n")
  end

  defp signed_http_envelope_payload(%{
         method: method,
         path: path,
         timestamp: timestamp,
         key_id: key_id,
         receipt: receipt,
         wallet: wallet,
         chain_id: chain_id,
         registry: registry,
         token_id: token_id
       }) do
    sig_nonce = "sig-nonce-#{System.unique_integer([:positive, :monotonic])}"
    expires = timestamp + 120

    components = [
      "@method",
      "@path",
      "x-siwa-receipt",
      "x-key-id",
      "x-timestamp",
      "x-agent-wallet-address",
      "x-agent-chain-id",
      "x-agent-registry-address",
      "x-agent-token-id"
    ]

    signature_params =
      "(#{Enum.map_join(components, " ", &~s("#{&1}"))})" <>
        ";created=#{timestamp};expires=#{expires};nonce=\"#{sig_nonce}\";keyid=\"#{key_id}\""

    signature_input = "sig1=" <> signature_params

    signing_message =
      [
        ~s("@method": #{String.downcase(method)}),
        ~s("@path": #{path}),
        ~s("x-siwa-receipt": #{receipt}),
        ~s("x-key-id": #{key_id}),
        ~s("x-timestamp": #{timestamp}),
        ~s("x-agent-wallet-address": #{wallet}),
        ~s("x-agent-chain-id": #{chain_id}),
        ~s("x-agent-registry-address": #{registry}),
        ~s("x-agent-token-id": #{token_id}),
        ~s("@signature-params": #{signature_params})
      ]
      |> Enum.join("\n")

    {signature_input, signing_message}
  end

  defp wait_until_expired!(expires_at_iso8601) when is_binary(expires_at_iso8601) do
    {:ok, expires_at, _offset} = DateTime.from_iso8601(expires_at_iso8601)
    remaining_ms = DateTime.diff(expires_at, DateTime.utc_now(), :millisecond) + 250

    if remaining_ms > 0 do
      receive do
      after
        remaining_ms -> :ok
      end
    else
      :ok
    end
  end
end
