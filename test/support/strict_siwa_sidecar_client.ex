defmodule TechTreeWeb.TestSupport.StrictSiwaSidecarClient do
  @moduledoc false

  @behaviour TechTree.SiwaSidecarClient

  @impl true
  def verify_http_request(conn, normalized_headers) do
    siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    secret = Keyword.fetch!(siwa_cfg, :shared_secret)
    body = conn.assigns[:raw_body]

    request = %{
      method: conn.method,
      path: conn.request_path,
      headers: normalized_headers,
      body: body
    }

    replay_store =
      Keyword.get(siwa_cfg, :test_replay_store, fn _replay_key, _expires_at -> :ok end)

    case Siwa.verify_authenticated_request(request,
           audience: "techtree",
           receipt_secret: secret,
           replay_store: replay_store
         ) do
      {:ok, verified} ->
        {:ok,
         %{
           status: 200,
           body: %{
             "ok" => true,
             "code" => "http_envelope_valid",
             "data" => %{
               "verified" => true,
               "walletAddress" => verified.claims["sub"],
               "chainId" => verified.claims["chain_id"],
               "keyId" => verified.claims["key_id"],
               "receiptExpiresAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
               "requiredHeaders" => Siwa.required_authenticated_request_headers(body),
               "requiredCoveredComponents" =>
                 Siwa.required_authenticated_request_components(normalized_headers, body),
               "coveredComponents" => verified.covered_components
             }
           }
         }}

      {:error, reason} ->
        {:ok,
         %{
           status: 422,
           body: %{
             "ok" => false,
             "code" => Atom.to_string(reason)
           }
         }}
    end
  end
end
