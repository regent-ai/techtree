defmodule TechTreeWeb.TestSupport.SiwaIntegrationSupport do
  @moduledoc false

  import ExUnit.Assertions, only: [flunk: 1]
  import Plug.Conn

  @spec with_siwa_headers(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def with_siwa_headers(conn, opts) do
    unique = System.unique_integer([:positive])
    wallet = Keyword.get(opts, :wallet, random_eth_address())
    registry = Keyword.get(opts, :registry_address, random_eth_address())
    chain_id = Keyword.get(opts, :chain_id, "11155111")
    token_id = Keyword.get(opts, :token_id, Integer.to_string(unique))

    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-agent-wallet-address", wallet)
    |> put_req_header("x-agent-chain-id", chain_id)
    |> put_req_header("x-agent-registry-address", registry)
    |> put_req_header("x-agent-token-id", token_id)
  end

  @spec attach_siwa_deny_handler() :: String.t()
  def attach_siwa_deny_handler do
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

  @spec put_sidecar_status(pos_integer()) :: :ok
  def put_sidecar_status(status) do
    Agent.update(TechTreeWeb.TestSupport.SiwaSidecarState, fn state ->
      Map.put(normalize_stub_state(state), :status, status)
    end)
  end

  @spec reset_sidecar_state() :: :ok
  def reset_sidecar_state do
    Agent.update(TechTreeWeb.TestSupport.SiwaSidecarState, fn _state ->
      %{status: 200, last_request: nil}
    end)
  end

  @spec sidecar_last_request() :: map() | nil
  def sidecar_last_request do
    Agent.get(TechTreeWeb.TestSupport.SiwaSidecarState, fn state ->
      normalize_stub_state(state).last_request
    end)
  end

  @spec random_eth_address() :: String.t()
  def random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end

  @spec available_port() :: :inet.port_number()
  def available_port do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  @spec with_external_siwa_sidecar((String.t(), String.t() -> result), keyword()) :: result
        when result: var
  def with_external_siwa_sidecar(fun, opts \\ []) do
    node_executable =
      System.find_executable("node") ||
        flunk("node executable is required for SIWA integration tests")

    _cast_executable =
      System.find_executable("cast") ||
        flunk("cast executable is required for SIWA integration tests")

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

  @spec configure_siwa_sidecar!(String.t(), String.t()) :: keyword()
  def configure_siwa_sidecar!(sidecar_url, shared_secret) do
    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])

    Application.put_env(:tech_tree, :siwa,
      internal_url: sidecar_url,
      shared_secret: shared_secret,
      skip_http_verify: false
    )

    original_siwa_cfg
  end

  @spec restore_siwa_config!(keyword()) :: :ok
  def restore_siwa_config!(siwa_cfg) do
    Application.put_env(:tech_tree, :siwa, siwa_cfg)
    :ok
  end

  @spec cast_wallet_address!(String.t()) :: String.t()
  def cast_wallet_address!(private_key) do
    {output, 0} =
      System.cmd("cast", ["wallet", "address", "--private-key", private_key],
        stderr_to_stdout: true
      )

    String.trim(output)
  end

  @spec cast_wallet_sign!(String.t(), String.t()) :: String.t()
  def cast_wallet_sign!(private_key, message) do
    {output, 0} =
      System.cmd("cast", ["wallet", "sign", "--private-key", private_key, message],
        stderr_to_stdout: true
      )

    String.trim(output)
  end

  @spec sig1_signature_header!(String.t(), String.t()) :: String.t()
  def sig1_signature_header!(private_key, message) do
    signature_hex = cast_wallet_sign!(private_key, message)

    "sig1=:" <>
      Base.encode64(Base.decode16!(String.trim_leading(signature_hex, "0x"), case: :mixed)) <> ":"
  end

  @spec siwe_message(String.t(), String.t(), integer()) :: String.t()
  def siwe_message(wallet, nonce, chain_id) do
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

  @spec signed_http_envelope_payload(map()) :: {String.t(), String.t()}
  def signed_http_envelope_payload(%{
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

  @spec wait_until_expired!(String.t()) :: :ok
  def wait_until_expired!(expires_at_iso8601) when is_binary(expires_at_iso8601) do
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

  defp normalize_stub_state(state) when is_map(state),
    do: Map.merge(%{status: 200, last_request: nil}, state)

  defp normalize_stub_state(status) when is_integer(status),
    do: %{status: status, last_request: nil}

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
             "chainId" => 11_155_111,
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
end
