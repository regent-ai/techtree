defmodule TechTreeWeb.Plugs.RequireAgentSiwa do
  @moduledoc false

  import Plug.Conn
  require Logger

  alias TechTree.Agents
  alias TechTree.Agents.AgentIdentity
  alias TechTreeWeb.ApiError

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

    with {:ok, agent_claims} <- verify_with_sidecar(conn, normalized_headers),
         {:ok, agent} <- upsert_current_agent(agent_claims),
         :ok <- ensure_agent_status_allowed(agent) do
      conn
      |> assign(:current_agent_claims, agent_claims)
      |> assign(:current_agent, agent)
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
    with {:ok, request_agent_claims} <- normalize_request_agent_claims(normalized_headers) do
      case siwa_sidecar_client().verify_http_request(conn, normalized_headers) do
        {:ok,
         %{
           status: 200,
           body: %{
             "ok" => true,
             "code" => "http_envelope_valid",
             "data" => data
           }
         }} ->
          normalize_verified_agent_claims(data, request_agent_claims)

        {:ok, %{status: status, body: body}} when is_integer(status) ->
          {:error, sidecar_deny_meta(status, body)}

        {:error, :missing_siwa_internal_url} ->
          {:error, %{reason: :missing_siwa_internal_url, source: :siwa_config}}

        {:error, :missing_siwa_shared_secret} ->
          {:error, %{reason: :missing_siwa_shared_secret, source: :siwa_config}}

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

      {:error, :missing_siwa_shared_secret} ->
        {:error, %{reason: :missing_siwa_shared_secret, source: :siwa_config}}

      {:error, deny_meta} when is_map(deny_meta) ->
        {:error, deny_meta}

      _ ->
        {:error, %{reason: :siwa_invalid_response, source: :sidecar_http}}
    end
  end

  @spec siwa_sidecar_client() :: module()
  defp siwa_sidecar_client do
    :tech_tree
    |> Application.get_env(:siwa, [])
    |> Keyword.get(:client, TechTree.SiwaSidecarClient)
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

  @spec normalize_verified_agent_claims(map(), map()) :: {:ok, map()} | {:error, map()}
  defp normalize_verified_agent_claims(data, request_agent_claims) when is_map(data) do
    with {:ok, wallet_value} <- fetch_required_value(data, "walletAddress", :sidecar_claims),
         {:ok, chain_id_value} <- fetch_required_value(data, "chainId", :sidecar_claims),
         {:ok, wallet} <- validate_hex_address(wallet_value, "walletAddress", :sidecar_claims),
         {:ok, chain_id} <- validate_positive_int(chain_id_value, "chainId", :sidecar_claims),
         :ok <- ensure_verified_binding("wallet_address", wallet, request_agent_claims),
         :ok <-
           ensure_verified_binding("chain_id", Integer.to_string(chain_id), request_agent_claims) do
      {:ok, request_agent_claims}
    end
  end

  defp normalize_verified_agent_claims(_data, _request_agent_claims),
    do: {:error, %{reason: :siwa_invalid_response, source: :sidecar_http}}

  @spec ensure_verified_binding(String.t(), String.t(), map()) :: :ok | {:error, map()}
  defp ensure_verified_binding(key, value, request_agent_claims) do
    if Map.fetch!(request_agent_claims, key) == value do
      :ok
    else
      {:error, %{reason: :receipt_binding_mismatch, source: :sidecar_claims}}
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

  @spec fetch_required_value(map(), String.t(), atom()) :: {:ok, String.t()} | {:error, map()}
  defp fetch_required_value(claims, key, source) do
    case claims[key] do
      value when is_binary(value) ->
        case String.trim(value) do
          "" ->
            {:error, %{reason: :missing_agent_headers, source: source, missing_headers: [key]}}

          trimmed ->
            {:ok, trimmed}
        end

      value when is_integer(value) ->
        {:ok, Integer.to_string(value)}

      _ ->
        {:error, %{reason: :missing_agent_headers, source: source, missing_headers: [key]}}
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

  @spec upsert_current_agent(map()) :: {:ok, AgentIdentity.t()} | {:error, map()}
  defp upsert_current_agent(agent_claims) do
    {:ok, Agents.upsert_verified_agent!(agent_claims)}
  rescue
    _ ->
      {:error, %{reason: :agent_status_lookup_failed, source: :agent_status}}
  end

  @spec ensure_agent_status_allowed(AgentIdentity.t()) :: :ok | {:error, map()}
  defp ensure_agent_status_allowed(%AgentIdentity{status: "active"}), do: :ok

  defp ensure_agent_status_allowed(%AgentIdentity{}),
    do: {:error, %{reason: :agent_banned, source: :agent_status}}

  @spec render_auth_result(Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp render_auth_result(conn, deny_meta) do
    emit_deny_metadata(conn, deny_meta)

    case Map.get(deny_meta, :reason) do
      :agent_banned ->
        ApiError.render_halted(conn, :forbidden, %{
          "code" => "agent_banned",
          "message" => "Agent is banned"
        })

      reason
      when reason in [
             :sidecar_request_failed,
             :siwa_invalid_response,
             :agent_status_lookup_failed
           ] ->
        ApiError.render_halted(conn, :service_unavailable, %{
          "code" => "siwa_unavailable",
          "message" => "Agent sign-in is temporarily unavailable"
        })

      :missing_siwa_internal_url ->
        ApiError.render_halted(conn, :internal_server_error, %{
          "code" => "siwa_unavailable",
          "message" => "Agent sign-in is temporarily unavailable"
        })

      :missing_siwa_shared_secret ->
        ApiError.render_halted(conn, :internal_server_error, %{
          "code" => "siwa_unavailable",
          "message" => "Agent sign-in is temporarily unavailable"
        })

      _ ->
        ApiError.render_halted(conn, :unauthorized, %{
          "code" => "agent_auth_required",
          "message" => "Valid SIWA agent auth required"
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
