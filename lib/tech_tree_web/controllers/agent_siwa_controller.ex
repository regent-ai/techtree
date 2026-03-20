defmodule TechTreeWeb.AgentSiwaController do
  use TechTreeWeb, :controller

  alias TechTreeWeb.ApiError

  @default_sidecar_connect_timeout_ms 2_000
  @default_sidecar_receive_timeout_ms 5_000

  @spec nonce(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def nonce(conn, params) do
    payload = %{
      "kind" => "nonce_request",
      "walletAddress" => Map.get(params, "walletAddress", Map.get(params, "address")),
      "chainId" => normalize_positive_int(Map.get(params, "chainId"), 1),
      "audience" => Map.get(params, "audience", "techtree")
    }

    proxy(conn, "/v1/nonce", payload)
  end

  @spec verify(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def verify(conn, params) do
    payload =
      %{
        "kind" => "verify_request",
        "walletAddress" => Map.get(params, "walletAddress", Map.get(params, "address")),
        "chainId" => normalize_positive_int(Map.get(params, "chainId"), 1),
        "nonce" => Map.get(params, "nonce"),
        "message" => Map.get(params, "message"),
        "signature" => Map.get(params, "signature")
      }
      |> maybe_put(
        "registryAddress",
        Map.get(params, "registryAddress", Map.get(params, "registry_address"))
      )
      |> maybe_put("tokenId", Map.get(params, "tokenId", Map.get(params, "token_id")))

    proxy(conn, "/v1/verify", payload)
  end

  @spec maybe_put(map(), String.t(), term()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec normalize_positive_int(term(), pos_integer()) :: pos_integer()
  defp normalize_positive_int(value, _fallback) when is_integer(value) and value > 0, do: value

  defp normalize_positive_int(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  defp normalize_positive_int(_value, fallback), do: fallback

  @spec proxy(Plug.Conn.t(), String.t(), map()) :: Plug.Conn.t()
  defp proxy(conn, path, body) do
    siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    base_url = Keyword.get(siwa_cfg, :internal_url, "http://localhost:3001")
    shared_secret = Keyword.get(siwa_cfg, :shared_secret, "")
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

    case Req.post(
           url: "#{base_url}#{path}",
           json: body,
           headers: [{"x-tech-tree-secret", shared_secret}],
           decode_body: false,
           connect_options: [timeout: connect_timeout_ms],
           receive_timeout: receive_timeout_ms
         ) do
      {:ok, %{status: status, body: resp_body, headers: resp_headers}} when is_integer(status) ->
        content_type = response_content_type(resp_headers)

        conn
        |> put_resp_content_type(content_type)
        |> Plug.Conn.send_resp(status, response_body(resp_body))

      {:error, reason} ->
        ApiError.render(conn, :bad_gateway, %{code: "siwa_unavailable", reason: inspect(reason)})
    end
  end

  @spec response_content_type(map() | [{String.t(), String.t()}]) :: String.t()
  defp response_content_type(headers) when is_map(headers) do
    case Map.get(headers, "content-type") do
      [value | _] when is_binary(value) and value != "" ->
        value |> String.split(";", parts: 2) |> hd() |> String.trim()

      value when is_binary(value) and value != "" ->
        value |> String.split(";", parts: 2) |> hd() |> String.trim()

      _ ->
        "application/json"
    end
  end

  defp response_content_type(headers) when is_list(headers) do
    case List.keyfind(headers, "content-type", 0) do
      {_name, value} when is_binary(value) and value != "" ->
        value |> String.split(";", parts: 2) |> hd() |> String.trim()

      _ ->
        "application/json"
    end
  end

  @spec response_body(term()) :: iodata()
  defp response_body(value) when is_binary(value), do: value
  defp response_body(value), do: Jason.encode!(value)

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
end
