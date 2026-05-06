defmodule TechTreeWeb.TestSupport.SiwaIntegrationSupport do
  @moduledoc false

  import Plug.Conn

  @receipt_secret "techtree-test-siwa-receipt-secret"

  @spec with_siwa_headers(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def with_siwa_headers(conn, opts) do
    unique = System.unique_integer([:positive])
    wallet = Keyword.get(opts, :wallet, random_eth_address())
    registry = Keyword.get(opts, :registry_address, random_eth_address())
    chain_id = Keyword.get(opts, :chain_id, "8453")
    token_id = Keyword.get(opts, :token_id, Integer.to_string(unique))
    receipt_audience = Keyword.get(opts, :receipt_audience, "techtree")

    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-agent-wallet-address", wallet)
    |> put_req_header("x-agent-chain-id", chain_id)
    |> put_req_header("x-agent-registry-address", registry)
    |> put_req_header("x-agent-token-id", token_id)
    |> put_req_header(
      "x-siwa-receipt",
      receipt_token(wallet, chain_id, registry, token_id, receipt_audience)
    )
  end

  @spec with_shared_siwa_signed_request(
          Plug.Conn.t(),
          String.t(),
          String.t(),
          String.t() | nil,
          keyword()
        ) :: Plug.Conn.t()
  def with_shared_siwa_signed_request(conn, method, path, body, opts \\ []) do
    {:ok, signer} = Siwa.LocalSigner.new()
    {:ok, wallet} = Siwa.LocalSigner.get_address(signer)

    chain_id = opts |> Keyword.get(:chain_id, 8_453) |> normalize_chain_id()
    registry = Keyword.get(opts, :registry_address, random_eth_address())
    token_id = Keyword.get(opts, :token_id, Integer.to_string(System.unique_integer([:positive])))
    audience = Keyword.get(opts, :audience, "techtree")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, receipt} =
      Siwa.create_receipt(
        %{
          "typ" => "siwa_receipt",
          "jti" => Ecto.UUID.generate(),
          "sub" => wallet,
          "aud" => audience,
          "chain_id" => chain_id,
          "nonce" => "nonce-#{System.unique_integer([:positive])}",
          "key_id" => wallet,
          "registry_address" => registry,
          "token_id" => token_id
        },
        receipt_secret: siwa_receipt_secret!(),
        now: now,
        ttl_ms: 600_000
      )

    {:ok, signed_request} =
      Siwa.sign_authenticated_request(
        %{method: method, path: path, body: body, headers: %{}},
        receipt.token,
        signer,
        audience: audience,
        receipt_secret: siwa_receipt_secret!(),
        created_at: now,
        expires_in_seconds: 120,
        nonce: "sig-nonce-#{System.unique_integer([:positive, :monotonic])}"
      )

    Enum.reduce(signed_request.headers, conn, fn {key, value}, acc ->
      put_req_header(acc, key, value)
    end)
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

  @spec put_siwa_status(pos_integer()) :: :ok
  def put_siwa_status(status) do
    Agent.update(TechTreeWeb.TestSupport.SiwaServerState, fn state ->
      Map.put(normalize_stub_state(state), :status, status)
    end)
  end

  @spec reset_siwa_server_state() :: :ok
  def reset_siwa_server_state do
    Agent.update(TechTreeWeb.TestSupport.SiwaServerState, fn _state ->
      %{status: 200, last_request: nil, last_audience: nil}
    end)
  end

  @spec siwa_last_request() :: map() | nil
  def siwa_last_request do
    Agent.get(TechTreeWeb.TestSupport.SiwaServerState, fn state ->
      normalize_stub_state(state).last_request
    end)
  end

  @spec siwa_last_audience() :: String.t() | nil
  def siwa_last_audience do
    Agent.get(TechTreeWeb.TestSupport.SiwaServerState, fn state ->
      normalize_stub_state(state).last_audience
    end)
  end

  @spec random_eth_address() :: String.t()
  def random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end

  @spec configure_siwa_server!(String.t()) :: keyword()
  def configure_siwa_server!(siwa_server_url) do
    original_siwa_cfg = Application.get_env(:tech_tree, :siwa, [])

    Application.put_env(:tech_tree, :siwa, internal_url: siwa_server_url)

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

  defp normalize_chain_id(value) when is_integer(value), do: value
  defp normalize_chain_id(value) when is_binary(value), do: String.to_integer(value)

  @spec siwa_receipt_secret!() :: String.t()
  def siwa_receipt_secret!, do: @receipt_secret

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
    do: Map.merge(%{status: 200, last_request: nil, last_audience: nil}, state)

  defp normalize_stub_state(status) when is_integer(status),
    do: %{status: status, last_request: nil, last_audience: nil}

  defp receipt_token(wallet, chain_id, registry, token_id, audience) do
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
      :crypto.mac(:hmac, :sha256, siwa_receipt_secret!(), payload)
      |> Base.url_encode64(padding: false)

    "#{payload}.#{signature}"
  end
end
