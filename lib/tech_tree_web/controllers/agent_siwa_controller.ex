defmodule TechTreeWeb.AgentSiwaController do
  use TechTreeWeb, :controller

  alias TechTreeWeb.ApiError

  @spec nonce(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def nonce(conn, params) do
    payload = %{
      "kind" => "nonce_request",
      "walletAddress" => Map.get(params, "walletAddress", Map.get(params, "address")),
      "chainId" => normalize_positive_int(Map.get(params, "chainId"), 8453),
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
        "chainId" => normalize_positive_int(Map.get(params, "chainId"), 8453),
        "nonce" => Map.get(params, "nonce"),
        "message" => Map.get(params, "message"),
        "signature" => Map.get(params, "signature")
      }
      |> maybe_put("registryAddress", Map.get(params, "registryAddress", Map.get(params, "registry_address")))
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

    case Req.post(
           url: "#{base_url}#{path}",
           json: body,
           headers: [{"x-tech-tree-secret", shared_secret}]
         ) do
      {:ok, %{status: 200, body: resp}} -> json(conn, resp)
      {:ok, %{status: status, body: resp}} -> conn |> put_status(status) |> json(resp)
      {:error, reason} -> ApiError.render(conn, :bad_gateway, %{code: "siwa_unavailable", reason: inspect(reason)})
    end
  end
end
