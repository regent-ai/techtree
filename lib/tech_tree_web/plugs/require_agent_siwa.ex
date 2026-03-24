defmodule TechTreeWeb.Plugs.RequireAgentSiwa do
  @moduledoc false

  import Plug.Conn
  require Logger

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Repo
  alias TechTreeWeb.ApiError

  @http_verify_path "/v1/http-verify"
  @default_sidecar_hmac_key_id "sidecar-internal-v1"
  @default_sidecar_connect_timeout_ms 2_000
  @default_sidecar_receive_timeout_ms 5_000
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
    normalized_headers = downcase_headers(conn.req_headers)

    with {:ok, agent_claims} <- extract_agent_claims(normalized_headers),
         :ok <- verify_with_sidecar(conn, normalized_headers),
         :ok <- ensure_agent_status_allowed(agent_claims) do
      assign(conn, :current_agent_claims, agent_claims)
    else
      {:error, deny_meta} -> unauthorized(conn, deny_meta)
      _ -> unauthorized(conn, %{reason: :siwa_auth_denied})
    end
  rescue
    error ->
      unauthorized(conn, %{
        reason: :siwa_exception,
        source: :exception,
        error: exception_name(error)
      })
  end

  @spec verify_with_sidecar(Plug.Conn.t(), map()) :: :ok | {:error, map()}
  defp verify_with_sidecar(conn, normalized_headers) do
    if siwa_skip_http_verify?() do
      :ok
    else
      do_verify_with_sidecar(conn, normalized_headers)
    end
  end

  @spec do_verify_with_sidecar(Plug.Conn.t(), map()) :: :ok | {:error, map()}
  defp do_verify_with_sidecar(conn, normalized_headers) do
    with {:ok,
          %{
            internal_url: internal_url,
            hmac_secret: hmac_secret,
            connect_timeout_ms: connect_timeout_ms,
            receive_timeout_ms: receive_timeout_ms
          }} <- fetch_siwa_http_config(),
         payload <- build_http_verify_payload(conn, normalized_headers),
         {:ok, payload_json} <- Jason.encode(payload),
         signed_headers <- sidecar_hmac_headers(hmac_secret, payload_json) do
      case Req.post(
             url: "#{internal_url}#{@http_verify_path}",
             body: payload_json,
             headers: [{"content-type", "application/json"} | signed_headers],
             connect_options: [timeout: connect_timeout_ms],
             receive_timeout: receive_timeout_ms
           ) do
        {:ok, %{status: 200, body: %{"ok" => true, "code" => "http_envelope_valid"}}} ->
          :ok

        {:ok, %{status: status, body: body}} when is_integer(status) ->
          {:error, sidecar_deny_meta(status, body)}

        {:error, reason} ->
          {:error,
           %{
             reason: :sidecar_request_failed,
             source: :sidecar_http,
             transport_error: normalize_transport_error(reason)
           }}
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

  @spec fetch_siwa_http_config() ::
          {:ok,
           %{
             internal_url: String.t(),
             hmac_secret: String.t(),
             connect_timeout_ms: pos_integer(),
             receive_timeout_ms: pos_integer()
           }}
          | {:error, :missing_siwa_internal_url | :missing_siwa_hmac_secret}
  defp fetch_siwa_http_config do
    siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    internal_url = Keyword.get(siwa_cfg, :internal_url)
    configured_secret = Keyword.get(siwa_cfg, :shared_secret, "")

    connect_timeout_ms =
      normalize_positive_timeout_ms(
        Keyword.get(siwa_cfg, :http_connect_timeout_ms),
        @default_sidecar_connect_timeout_ms
      )

    receive_timeout_ms =
      normalize_positive_timeout_ms(
        Keyword.get(siwa_cfg, :http_receive_timeout_ms),
        @default_sidecar_receive_timeout_ms
      )

    env_secret = System.get_env("SIWA_HMAC_SECRET", "")

    secret =
      case configured_secret do
        value when is_binary(value) and value != "" -> value
        _ -> env_secret
      end

    valid_internal_url? = is_binary(internal_url) and internal_url != ""
    valid_secret? = is_binary(secret) and secret != ""

    if valid_internal_url? and valid_secret? do
      {:ok,
       %{
         internal_url: internal_url,
         hmac_secret: secret,
         connect_timeout_ms: connect_timeout_ms,
         receive_timeout_ms: receive_timeout_ms
       }}
    else
      if not valid_internal_url? do
        {:error, :missing_siwa_internal_url}
      else
        {:error, :missing_siwa_hmac_secret}
      end
    end
  end

  @spec normalize_positive_timeout_ms(term(), pos_integer()) :: pos_integer()
  defp normalize_positive_timeout_ms(value, _fallback) when is_integer(value) and value > 0,
    do: value

  defp normalize_positive_timeout_ms(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  defp normalize_positive_timeout_ms(_value, fallback), do: fallback

  @spec build_http_verify_payload(Plug.Conn.t(), map()) :: map()
  defp build_http_verify_payload(conn, normalized_headers) do
    base_payload = %{
      "kind" => "http_verify_request",
      "method" => conn.method,
      "path" => conn.request_path,
      "headers" => normalized_headers
    }

    case Map.get(normalized_headers, "content-digest") do
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

  @spec extract_agent_claims(map()) :: {:ok, map()} | {:error, map()}
  defp extract_agent_claims(normalized_headers) do
    with {:ok, required_headers} <- fetch_required_headers(normalized_headers),
         {:ok, wallet} <-
           validate_hex_address(
             required_headers["x-agent-wallet-address"],
             "x-agent-wallet-address"
           ),
         {:ok, chain_id} <-
           validate_positive_int(required_headers["x-agent-chain-id"], "x-agent-chain-id"),
         {:ok, registry} <-
           validate_hex_address(
             required_headers["x-agent-registry-address"],
             "x-agent-registry-address"
           ),
         {:ok, token_id} <-
           validate_positive_int(required_headers["x-agent-token-id"], "x-agent-token-id") do
      {:ok,
       %{
         "wallet_address" => wallet,
         "chain_id" => Integer.to_string(chain_id),
         "registry_address" => registry,
         "token_id" => Integer.to_string(token_id),
         "label" => fetch_optional_header(normalized_headers, "x-agent-label")
       }}
    end
  end

  @spec fetch_required_headers(map()) :: {:ok, map()} | {:error, map()}
  defp fetch_required_headers(normalized_headers) do
    missing =
      Enum.filter(@required_agent_headers, fn header ->
        case Map.get(normalized_headers, header) do
          value when is_binary(value) -> String.trim(value) == ""
          _ -> true
        end
      end)

    if missing == [] do
      values =
        Map.new(@required_agent_headers, fn header ->
          value = normalized_headers |> Map.fetch!(header) |> String.trim()
          {header, value}
        end)

      {:ok, values}
    else
      {:error,
       %{reason: :missing_agent_headers, source: :request_headers, missing_headers: missing}}
    end
  end

  @spec fetch_optional_header(map(), String.t()) :: String.t() | nil
  defp fetch_optional_header(normalized_headers, key) do
    case Map.get(normalized_headers, String.downcase(key)) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
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

  @spec ensure_agent_status_allowed(map()) :: :ok | {:error, map()}
  defp ensure_agent_status_allowed(agent_claims) do
    chain_id = String.to_integer(agent_claims["chain_id"])
    token_id = Decimal.new(agent_claims["token_id"])

    case Repo.get_by(AgentIdentity,
           chain_id: chain_id,
           registry_address: agent_claims["registry_address"],
           token_id: token_id
         ) do
      nil ->
        :ok

      %AgentIdentity{status: "active"} ->
        :ok

      %AgentIdentity{} ->
        {:error, %{reason: :agent_banned, source: :agent_status}}
    end
  rescue
    _ ->
      {:error, %{reason: :agent_status_lookup_failed, source: :agent_status}}
  end

  @spec unauthorized(Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp unauthorized(conn, deny_meta) do
    emit_deny_metadata(conn, deny_meta)

    case Map.get(deny_meta, :reason) do
      :agent_banned ->
        ApiError.render_halted(conn, :forbidden, %{
          code: "agent_banned",
          message: "Agent is banned"
        })

      _ ->
        ApiError.render_halted(conn, :unauthorized, %{
          code: "agent_auth_required",
          message: "Valid SIWA agent auth required"
        })
    end
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
