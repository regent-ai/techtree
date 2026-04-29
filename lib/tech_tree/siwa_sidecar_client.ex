defmodule TechTree.SiwaSidecarClient do
  @moduledoc false

  @callback verify_http_request(Plug.Conn.t(), map()) ::
              {:ok, Req.Response.t()} | {:error, term()}

  @http_verify_path "/v1/agent/siwa/http-verify"
  @default_key_id "sidecar-internal-v1"
  @default_connect_timeout_ms 2_000
  @default_receive_timeout_ms 5_000

  @spec verify_http_request(Plug.Conn.t(), map()) ::
          {:ok, Req.Response.t()} | {:error, term()} | {:error, :missing_siwa_internal_url}
  def verify_http_request(conn, normalized_headers) do
    with {:ok, config} <- fetch_config(),
         payload <- build_http_verify_payload(conn, normalized_headers),
         {:ok, payload_json} <- Jason.encode(payload) do
      timestamp = Integer.to_string(System.system_time(:second))

      Req.post(
        url: "#{config.internal_url}#{@http_verify_path}",
        body: payload_json,
        headers: [
          {"content-type", "application/json"},
          {"x-sidecar-key-id", config.key_id},
          {"x-sidecar-timestamp", timestamp},
          {"x-sidecar-signature", signature(config.secret, timestamp, payload_json)}
        ],
        connect_options: [timeout: config.connect_timeout_ms],
        receive_timeout: config.receive_timeout_ms
      )
    end
  end

  @spec fetch_config() ::
          {:ok,
           %{
             internal_url: String.t(),
             secret: String.t(),
             key_id: String.t(),
             connect_timeout_ms: pos_integer(),
             receive_timeout_ms: pos_integer()
           }}
          | {:error, :missing_siwa_internal_url}
          | {:error, :missing_siwa_shared_secret}
  defp fetch_config do
    siwa_cfg = Application.get_env(:tech_tree, :siwa, [])

    with {:ok, internal_url} <- fetch_required_trimmed(siwa_cfg, :internal_url),
         {:ok, secret} <- fetch_required_trimmed(siwa_cfg, :shared_secret) do
      {:ok,
       %{
         internal_url: internal_url,
         secret: secret,
         key_id: fetch_key_id(siwa_cfg),
         connect_timeout_ms:
           normalize_positive_timeout_ms(
             Keyword.get(siwa_cfg, :http_connect_timeout_ms),
             @default_connect_timeout_ms
           ),
         receive_timeout_ms:
           normalize_positive_timeout_ms(
             Keyword.get(siwa_cfg, :http_receive_timeout_ms),
             @default_receive_timeout_ms
           )
       }}
    else
      {:error, :internal_url} -> {:error, :missing_siwa_internal_url}
      {:error, :shared_secret} -> {:error, :missing_siwa_shared_secret}
    end
  end

  @spec fetch_required_trimmed(keyword(), atom()) :: {:ok, String.t()} | {:error, atom()}
  defp fetch_required_trimmed(config, key) do
    case Keyword.get(config, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, key}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, key}
    end
  end

  @spec fetch_key_id(keyword()) :: String.t()
  defp fetch_key_id(config) do
    case Keyword.get(config, :hmac_key_id) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> @default_key_id
          trimmed -> trimmed
        end

      _ ->
        @default_key_id
    end
  end

  @spec normalize_positive_timeout_ms(term(), pos_integer()) :: pos_integer()
  defp normalize_positive_timeout_ms(value, _default) when is_integer(value) and value > 0,
    do: value

  defp normalize_positive_timeout_ms(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp normalize_positive_timeout_ms(_value, default), do: default

  @spec build_http_verify_payload(Plug.Conn.t(), map()) :: map()
  defp build_http_verify_payload(conn, normalized_headers) do
    base_payload = %{
      "kind" => "http_verify_request",
      "method" => conn.method,
      "path" => conn.request_path,
      "headers" => normalized_headers
    }

    case conn.assigns[:raw_body] do
      value when is_binary(value) -> Map.put(base_payload, "body", value)
      _ -> base_payload
    end
  end

  @spec signature(String.t(), String.t(), String.t()) :: String.t()
  defp signature(secret, timestamp, payload_json) do
    signed_payload = "POST\n#{@http_verify_path}\n#{timestamp}\n#{payload_json}"

    "sha256=" <>
      (:crypto.mac(:hmac, :sha256, secret, signed_payload)
       |> Base.encode16(case: :lower))
  end
end
