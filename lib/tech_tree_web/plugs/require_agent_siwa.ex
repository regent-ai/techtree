defmodule TechTreeWeb.Plugs.RequireAgentSiwa do
  @moduledoc false

  import Plug.Conn
  require Logger

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Repo
  alias TechTree.SiwaReceipt
  alias TechTreeWeb.ApiError

  @http_verify_path "/v1/agent/siwa/http-verify"
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
  @audience "techtree"

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    normalized_headers = downcase_headers(conn.req_headers)

    with :ok <- verify_receipt_audience(normalized_headers),
         {:ok, agent_claims} <- verify_with_sidecar(conn, normalized_headers),
         :ok <- ensure_agent_status_allowed(agent_claims) do
      assign(conn, :current_agent_claims, agent_claims)
    else
      {:error, deny_meta} when is_map(deny_meta) -> render_auth_result(conn, deny_meta)
      _ -> render_auth_result(conn, %{reason: :siwa_auth_denied})
    end
  end

  @spec verify_with_sidecar(Plug.Conn.t(), map()) :: {:ok, map()} | {:error, map()}
  defp verify_with_sidecar(conn, normalized_headers) do
    do_verify_with_sidecar(conn, normalized_headers)
  end

  @spec do_verify_with_sidecar(Plug.Conn.t(), map()) :: {:ok, map()} | {:error, map()}
  defp do_verify_with_sidecar(conn, normalized_headers) do
    with {:ok,
          %{
            internal_url: internal_url,
            connect_timeout_ms: connect_timeout_ms,
            receive_timeout_ms: receive_timeout_ms
          }} <- fetch_siwa_http_config(),
         {:ok, _canonical_request_claims} <- normalize_request_agent_claims(normalized_headers),
         payload <- build_http_verify_payload(conn, normalized_headers),
         {:ok, payload_json} <- Jason.encode(payload) do
      case Req.post(
             url: "#{internal_url}#{@http_verify_path}",
             body: payload_json,
             headers: [{"content-type", "application/json"}],
             connect_options: [timeout: connect_timeout_ms],
             receive_timeout: receive_timeout_ms
           ) do
        {:ok,
         %{
           status: 200,
           body: %{
             "ok" => true,
             "code" => "http_envelope_valid",
             "data" => %{"agent_claims" => claims}
           }
         }} ->
          normalize_sidecar_agent_claims(claims)

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

      {:error, deny_meta} when is_map(deny_meta) ->
        {:error, deny_meta}

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

  @spec fetch_siwa_http_config() ::
          {:ok,
           %{
             internal_url: String.t(),
             connect_timeout_ms: pos_integer(),
             receive_timeout_ms: pos_integer()
           }}
          | {:error, :missing_siwa_internal_url}
  defp fetch_siwa_http_config do
    siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    internal_url = Keyword.get(siwa_cfg, :internal_url)

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

    if is_binary(internal_url) and internal_url != "" do
      {:ok,
       %{
         internal_url: internal_url,
         connect_timeout_ms: connect_timeout_ms,
         receive_timeout_ms: receive_timeout_ms
       }}
    else
      {:error, :missing_siwa_internal_url}
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
      value when is_binary(value) and value != "" -> Map.put(base_payload, "body_digest", value)
      _ -> base_payload
    end
  end

  @spec normalize_request_agent_claims(map()) :: {:ok, map()} | {:error, map()}
  defp normalize_request_agent_claims(headers) do
    with {:ok, required_headers} <-
           fetch_required_values(headers, @required_agent_headers, :request_headers),
         {:ok, wallet} <-
           validate_hex_address(
             required_headers["x-agent-wallet-address"],
             "x-agent-wallet-address",
             :request_headers
           ),
         {:ok, chain_id} <-
           validate_positive_int(
             required_headers["x-agent-chain-id"],
             "x-agent-chain-id",
             :request_headers
           ),
         {:ok, registry} <-
           validate_hex_address(
             required_headers["x-agent-registry-address"],
             "x-agent-registry-address",
             :request_headers
           ),
         {:ok, token_id} <-
           validate_positive_int(
             required_headers["x-agent-token-id"],
             "x-agent-token-id",
             :request_headers
           ) do
      {:ok,
       %{
         "wallet_address" => wallet,
         "chain_id" => Integer.to_string(chain_id),
         "registry_address" => registry,
         "token_id" => Integer.to_string(token_id),
         "label" => fetch_optional_value(headers, "x-agent-label")
       }}
    end
  end

  @spec normalize_sidecar_agent_claims(map()) :: {:ok, map()} | {:error, map()}
  defp normalize_sidecar_agent_claims(claims) do
    required_claims = ["wallet_address", "chain_id", "registry_address", "token_id"]

    with {:ok, required_claims} <-
           fetch_required_values(claims, required_claims, :sidecar_claims),
         {:ok, wallet} <-
           validate_hex_address(
             required_claims["wallet_address"],
             "wallet_address",
             :sidecar_claims
           ),
         {:ok, chain_id} <-
           validate_positive_int(required_claims["chain_id"], "chain_id", :sidecar_claims),
         {:ok, registry} <-
           validate_hex_address(
             required_claims["registry_address"],
             "registry_address",
             :sidecar_claims
           ),
         {:ok, token_id} <-
           validate_positive_int(required_claims["token_id"], "token_id", :sidecar_claims) do
      {:ok,
       %{
         "wallet_address" => wallet,
         "chain_id" => Integer.to_string(chain_id),
         "registry_address" => registry,
         "token_id" => Integer.to_string(token_id),
         "label" => fetch_optional_value(claims, "label")
       }}
    end
  end

  @spec fetch_required_values(map(), [String.t()], atom()) :: {:ok, map()} | {:error, map()}
  defp fetch_required_values(claims, keys, source) do
    missing =
      Enum.filter(keys, fn key ->
        case Map.get(claims, key) do
          value when is_binary(value) -> String.trim(value) == ""
          _ -> true
        end
      end)

    if missing == [] do
      values =
        Map.new(keys, fn key ->
          value = claims |> Map.fetch!(key) |> String.trim()
          {key, value}
        end)

      {:ok, values}
    else
      {:error, %{reason: :missing_agent_headers, source: source, missing_headers: missing}}
    end
  end

  @spec fetch_optional_value(map(), String.t()) :: String.t() | nil
  defp fetch_optional_value(claims, key) do
    case claims[key] do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  @spec validate_hex_address(String.t(), String.t(), atom()) ::
          {:ok, String.t()} | {:error, map()}
  defp validate_hex_address(value, header, source) do
    if value =~ @hex_address_regex do
      {:ok, String.downcase(value)}
    else
      {:error, %{reason: :invalid_agent_header, source: source, invalid_header: header}}
    end
  end

  @spec validate_positive_int(String.t(), String.t(), atom()) ::
          {:ok, integer()} | {:error, map()}
  defp validate_positive_int(value, header, source) do
    if value =~ @positive_int_regex do
      {:ok, String.to_integer(value)}
    else
      {:error, %{reason: :invalid_agent_header, source: source, invalid_header: header}}
    end
  rescue
    _ ->
      {:error, %{reason: :invalid_agent_header, source: source, invalid_header: header}}
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
  end

  defp verify_receipt_audience(headers) do
    case fetch_shared_secret() do
      {:ok, secret} ->
        case SiwaReceipt.verify_request_headers(headers, audience: @audience, secret: secret) do
          {:ok, _claims} -> :ok
          {:error, reason} -> {:error, %{reason: reason, source: :receipt}}
        end

      {:error, reason} ->
        {:error, %{reason: reason, source: :siwa_config}}
    end
  end

  defp fetch_shared_secret do
    case Application.get_env(:tech_tree, :siwa, []) |> Keyword.get(:shared_secret) do
      secret when is_binary(secret) ->
        case String.trim(secret) do
          "" -> {:error, :missing_siwa_shared_secret}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, :missing_siwa_shared_secret}
    end
  end

  @spec render_auth_result(Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp render_auth_result(conn, deny_meta) do
    emit_deny_metadata(conn, deny_meta)

    case Map.get(deny_meta, :reason) do
      :agent_banned ->
        ApiError.render_halted(conn, :forbidden, %{
          code: "agent_banned",
          message: "Agent is banned"
        })

      reason
      when reason in [
             :sidecar_request_failed,
             :siwa_invalid_response,
             :agent_status_lookup_failed
           ] ->
        ApiError.render_halted(conn, :service_unavailable, %{
          code: "siwa_unavailable",
          message: "Agent sign-in is temporarily unavailable"
        })

      :missing_siwa_internal_url ->
        ApiError.render_halted(conn, :internal_server_error, %{
          code: "siwa_unavailable",
          message: "Agent sign-in is temporarily unavailable"
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
end
