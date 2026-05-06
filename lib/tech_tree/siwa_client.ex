defmodule TechTree.SiwaClient do
  @moduledoc false

  @callback verify_http_request(Plug.Conn.t(), map()) ::
              {:ok, Req.Response.t()} | {:error, term()}

  @http_verify_path "/v1/agent/siwa/http-verify"
  @audience "techtree"
  @default_connect_timeout_ms 2_000
  @default_receive_timeout_ms 5_000

  @spec verify_http_request(Plug.Conn.t(), map()) ::
          {:ok, Req.Response.t()} | {:error, term()} | {:error, :missing_siwa_internal_url}
  def verify_http_request(conn, normalized_headers) do
    with {:ok, config} <- fetch_config() do
      Req.post(
        url: "#{config.internal_url}#{@http_verify_path}",
        json: build_http_verify_payload(conn, normalized_headers),
        headers: [{"x-siwa-audience", @audience}],
        connect_options: [timeout: config.connect_timeout_ms],
        receive_timeout: config.receive_timeout_ms
      )
    end
  end

  @spec fetch_config() ::
          {:ok,
           %{
             internal_url: String.t(),
             connect_timeout_ms: pos_integer(),
             receive_timeout_ms: pos_integer()
           }}
          | {:error, :missing_siwa_internal_url}
  defp fetch_config do
    siwa_cfg = Application.get_env(:tech_tree, :siwa, [])

    with {:ok, internal_url} <- fetch_required_trimmed(siwa_cfg, :internal_url) do
      {:ok,
       %{
         internal_url: internal_url,
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
      "method" => conn.method,
      "path" => signed_path(conn),
      "headers" => normalized_headers
    }

    case conn.assigns[:raw_body] do
      value when is_binary(value) -> Map.put(base_payload, "body", value)
      _ -> base_payload
    end
  end

  @spec signed_path(Plug.Conn.t()) :: String.t()
  defp signed_path(%{request_path: path, query_string: ""}), do: path
  defp signed_path(%{request_path: path, query_string: query}), do: path <> "?" <> query
end
