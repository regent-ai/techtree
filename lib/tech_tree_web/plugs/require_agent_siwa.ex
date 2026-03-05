defmodule TechTreeWeb.Plugs.RequireAgentSiwa do
  @moduledoc false

  import Plug.Conn
  require Logger

  alias TechTreeWeb.ApiError

  @http_verify_path "/v1/http-verify"
  @default_sidecar_hmac_key_id "sidecar-internal-v1"
  @deny_telemetry_event [:tech_tree, :agent, :siwa, :deny]
  @required_agent_headers [
    "x-agent-wallet-address",
    "x-agent-chain-id",
    "x-agent-registry-address",
    "x-agent-token-id"
  ]
  @hex_address_regex ~r/^0x[0-9a-fA-F]{40}$/
  @positive_int_regex ~r/^[1-9][0-9]*$/

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    with :ok <- verify_with_sidecar(conn),
         {:ok, agent_claims} <- extract_agent_claims(conn) do
      assign(conn, :current_agent_claims, agent_claims)
    else
      {:error, deny_meta} -> unauthorized(conn, deny_meta)
      _ -> unauthorized(conn, %{reason: :siwa_auth_denied})
    end
  rescue
    error -> unauthorized(conn, %{reason: :siwa_exception, source: :exception, error: exception_name(error)})
  end

  @spec verify_with_sidecar(Plug.Conn.t()) :: :ok | {:error, map()}
  defp verify_with_sidecar(conn) do
    if siwa_skip_http_verify?() do
      :ok
    else
      do_verify_with_sidecar(conn)
    end
  end

  @spec do_verify_with_sidecar(Plug.Conn.t()) :: :ok | {:error, map()}
  defp do_verify_with_sidecar(conn) do
    with {:ok, internal_url} <- fetch_siwa_internal_url(),
         {:ok, hmac_secret} <- fetch_siwa_hmac_secret(),
         payload <- build_http_verify_payload(conn),
         {:ok, payload_json} <- Jason.encode(payload),
         signed_headers <- sidecar_hmac_headers(hmac_secret, payload_json) do
      case Req.post(
             url: "#{internal_url}#{@http_verify_path}",
             body: payload_json,
             headers: [{"content-type", "application/json"} | signed_headers]
           ) do
        {:ok, %{status: 200, body: %{"ok" => true}}} ->
          :ok

        {:ok, %{status: status, body: body}} when is_integer(status) ->
          {:error, sidecar_deny_meta(status, body)}

        {:error, reason} ->
          {:error,
           %{reason: :sidecar_request_failed, source: :sidecar_http, transport_error: normalize_transport_error(reason)}}
      end
    else
      {:error, :missing_siwa_internal_url} ->
        {:error, %{reason: :missing_siwa_internal_url, source: :siwa_config}}

      {:error, :missing_siwa_hmac_secret} ->
        {:error, %{reason: :missing_siwa_hmac_secret, source: :siwa_config}}

      _ ->
        {:error, %{reason: :siwa_invalid_response, source: :sidecar_http}}
    end
  end

  @spec sidecar_deny_meta(integer(), term()) :: map()
  defp sidecar_deny_meta(status, body) do
    %{reason: :"sidecar_http_#{status}", source: :sidecar_http, sidecar_status: status}
    |> maybe_put_sidecar_code(body)
  end

  @spec maybe_put_sidecar_code(map(), term()) :: map()
  defp maybe_put_sidecar_code(metadata, %{"code" => code}) when is_binary(code) and code != "" do
    Map.put(metadata, :sidecar_code, code)
  end

  defp maybe_put_sidecar_code(metadata, _body), do: metadata

  @spec normalize_transport_error(term()) :: atom()
  defp normalize_transport_error(error) do
    case error do
      reason when is_atom(reason) -> reason
      %{reason: reason} when is_atom(reason) -> reason
      _ -> :unknown_transport_error
    end
  rescue
    _ -> :unknown_transport_error
  end

  @spec siwa_skip_http_verify?() :: boolean()
  defp siwa_skip_http_verify? do
    siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    Keyword.get(siwa_cfg, :skip_http_verify, false) == true
  end

  @spec fetch_siwa_internal_url() :: {:ok, String.t()} | {:error, :missing_siwa_internal_url}
  defp fetch_siwa_internal_url do
    siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    internal_url = Keyword.get(siwa_cfg, :internal_url)

    case internal_url do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :missing_siwa_internal_url}
    end
  end

  @spec fetch_siwa_hmac_secret() :: {:ok, String.t()} | {:error, :missing_siwa_hmac_secret}
  defp fetch_siwa_hmac_secret do
    siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    configured_secret = Keyword.get(siwa_cfg, :shared_secret, "")
    env_secret = System.get_env("SIWA_HMAC_SECRET", "")

    secret =
      case configured_secret do
        value when is_binary(value) and value != "" -> value
        _ -> env_secret
      end

    case secret do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :missing_siwa_hmac_secret}
    end
  end

  @spec build_http_verify_payload(Plug.Conn.t()) :: map()
  defp build_http_verify_payload(conn) do
    headers = downcase_headers(conn.req_headers)

    base_payload = %{
      "kind" => "http_verify_request",
      "method" => conn.method,
      "path" => conn.request_path,
      "headers" => headers
    }

    case Map.get(headers, "content-digest") do
      value when is_binary(value) and value != "" -> Map.put(base_payload, "bodyDigest", value)
      _ -> base_payload
    end
  end

  @spec sidecar_hmac_headers(String.t(), String.t()) :: [{String.t(), String.t()}]
  defp sidecar_hmac_headers(hmac_secret, payload_json) do
    timestamp = Integer.to_string(System.os_time(:second))
    signature = sidecar_hmac_signature(hmac_secret, timestamp, payload_json)

    [
      {"x-sidecar-key-id", sidecar_hmac_key_id()},
      {"x-sidecar-timestamp", timestamp},
      {"x-sidecar-signature", "sha256=#{signature}"}
    ]
  end

  @spec sidecar_hmac_signature(String.t(), String.t(), String.t()) :: String.t()
  defp sidecar_hmac_signature(secret, timestamp, payload_json) do
    canonical_payload = "POST\n#{@http_verify_path}\n#{timestamp}\n#{payload_json}"

    :crypto.mac(:hmac, :sha256, secret, canonical_payload)
    |> Base.encode16(case: :lower)
  end

  @spec sidecar_hmac_key_id() :: String.t()
  defp sidecar_hmac_key_id do
    System.get_env("SIWA_HMAC_KEY_ID", @default_sidecar_hmac_key_id)
  end

  @spec extract_agent_claims(Plug.Conn.t()) :: {:ok, map()} | {:error, map()}
  defp extract_agent_claims(conn) do
    with {:ok, required_headers} <- fetch_required_headers(conn),
         {:ok, wallet} <- validate_hex_address(required_headers["x-agent-wallet-address"], "x-agent-wallet-address"),
         {:ok, chain_id} <- validate_positive_int(required_headers["x-agent-chain-id"], "x-agent-chain-id"),
         {:ok, registry} <- validate_hex_address(required_headers["x-agent-registry-address"], "x-agent-registry-address"),
         {:ok, token_id} <- validate_positive_int(required_headers["x-agent-token-id"], "x-agent-token-id") do
      {:ok,
       %{
         "wallet_address" => wallet,
         "chain_id" => Integer.to_string(chain_id),
         "registry_address" => registry,
         "token_id" => Integer.to_string(token_id),
         "label" => fetch_optional_header(conn, "x-agent-label")
       }}
    end
  end

  @spec fetch_required_headers(Plug.Conn.t()) :: {:ok, map()} | {:error, map()}
  defp fetch_required_headers(conn) do
    normalized = downcase_headers(conn.req_headers)

    missing =
      Enum.filter(@required_agent_headers, fn header ->
        case Map.get(normalized, header) do
          value when is_binary(value) -> String.trim(value) == ""
          _ -> true
        end
      end)

    if missing == [] do
      values =
        Map.new(@required_agent_headers, fn header ->
          value = normalized |> Map.fetch!(header) |> String.trim()
          {header, value}
        end)

      {:ok, values}
    else
      {:error, %{reason: :missing_agent_headers, source: :request_headers, missing_headers: missing}}
    end
  end

  @spec fetch_optional_header(Plug.Conn.t(), String.t()) :: String.t() | nil
  defp fetch_optional_header(conn, key) do
    case fetch_normalized_header(conn, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  @spec fetch_normalized_header(Plug.Conn.t(), String.t()) :: {:ok, String.t()} | :error
  defp fetch_normalized_header(conn, key) do
    case get_req_header(conn, key) do
      [value | _rest] when is_binary(value) ->
        normalized = String.trim(value)
        if normalized == "", do: :error, else: {:ok, normalized}

      _ ->
        :error
    end
  end

  @spec validate_hex_address(String.t(), String.t()) :: {:ok, String.t()} | {:error, map()}
  defp validate_hex_address(value, header) do
    if value =~ @hex_address_regex do
      {:ok, value}
    else
      {:error, %{reason: :invalid_agent_header, source: :request_headers, invalid_header: header}}
    end
  end

  @spec validate_positive_int(String.t(), String.t()) :: {:ok, integer()} | {:error, map()}
  defp validate_positive_int(value, header) do
    if value =~ @positive_int_regex do
      {:ok, String.to_integer(value)}
    else
      {:error, %{reason: :invalid_agent_header, source: :request_headers, invalid_header: header}}
    end
  rescue
    _ ->
      {:error, %{reason: :invalid_agent_header, source: :request_headers, invalid_header: header}}
  end

  @spec downcase_headers([{binary(), binary()}]) :: map()
  defp downcase_headers(headers) do
    Map.new(headers, fn {key, value} -> {String.downcase(key), value} end)
  end

  @spec unauthorized(Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp unauthorized(conn, deny_meta) do
    emit_deny_metadata(conn, deny_meta)

    ApiError.render_halted(conn, :unauthorized, %{
      code: "agent_auth_required",
      message: "Valid SIWA agent auth required"
    })
  end

  @spec emit_deny_metadata(Plug.Conn.t(), map()) :: :ok
  defp emit_deny_metadata(conn, deny_meta) do
    metadata = deny_metadata(conn, deny_meta)

    :telemetry.execute(@deny_telemetry_event, %{count: 1}, metadata)
    Logger.warning("agent SIWA auth denied", Map.to_list(metadata))
    :ok
  rescue
    _ -> :ok
  end

  @spec deny_metadata(Plug.Conn.t(), map()) :: map()
  defp deny_metadata(conn, deny_meta) do
    %{
      reason: Map.get(deny_meta, :reason, :siwa_auth_denied),
      source: Map.get(deny_meta, :source, :unknown),
      method: conn.method,
      request_path: conn.request_path
    }
    |> maybe_put(:sidecar_status, Map.get(deny_meta, :sidecar_status))
    |> maybe_put(:sidecar_code, Map.get(deny_meta, :sidecar_code))
    |> maybe_put(:transport_error, Map.get(deny_meta, :transport_error))
    |> maybe_put(:missing_headers, Map.get(deny_meta, :missing_headers))
    |> maybe_put(:invalid_header, Map.get(deny_meta, :invalid_header))
    |> maybe_put(:error, Map.get(deny_meta, :error))
  end

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(metadata, _key, nil), do: metadata
  defp maybe_put(metadata, _key, []), do: metadata
  defp maybe_put(metadata, key, value), do: Map.put(metadata, key, value)

  @spec exception_name(Exception.t()) :: atom()
  defp exception_name(error) do
    case error do
      %{__struct__: module} when is_atom(module) -> module
      _ -> :unknown_exception
    end
  end
end
