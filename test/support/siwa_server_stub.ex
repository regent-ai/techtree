defmodule TechTreeWeb.TestSupport.SiwaServerStub do
  @moduledoc false

  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case {conn.method, conn.request_path} do
      {"POST", "/v1/agent/siwa/http-verify"} ->
        {:ok, raw_body, conn} = read_body(conn)
        audience = conn |> get_req_header("x-siwa-audience") |> List.first()

        parsed_body =
          case Jason.decode(raw_body) do
            {:ok, decoded} -> decoded
            _ -> %{"body" => raw_body}
          end

        configured_status =
          Agent.get_and_update(TechTreeWeb.TestSupport.SiwaServerState, fn state ->
            normalized_state =
              case state do
                %{status: current_status} = map when is_integer(current_status) -> map
                value when is_integer(value) -> %{status: value}
                _ -> %{status: 200}
              end

            updated_state =
              normalized_state
              |> Map.put(:last_request, parsed_body)
              |> Map.put(:last_audience, audience)

            {Map.get(normalized_state, :status, 200), updated_state}
          end)

        status =
          if audience == "techtree", do: configured_status, else: 401

        body =
          case status do
            200 ->
              headers = Map.get(parsed_body, "headers", %{})

              Jason.encode!(%{
                ok: true,
                code: "http_envelope_valid",
                data: %{
                  verified: true,
                  walletAddress: Map.get(headers, "x-agent-wallet-address"),
                  chainId: String.to_integer(Map.get(headers, "x-agent-chain-id", "0")),
                  keyId: Map.get(headers, "x-key-id"),
                  agent_claims: %{
                    wallet_address: Map.get(headers, "x-agent-wallet-address"),
                    chain_id: Map.get(headers, "x-agent-chain-id"),
                    registry_address: Map.get(headers, "x-agent-registry-address"),
                    token_id: Map.get(headers, "x-agent-token-id")
                  },
                  receiptExpiresAt: "2026-04-28T00:00:00.000Z",
                  requiredHeaders: [
                    "x-siwa-receipt",
                    "signature",
                    "signature-input",
                    "x-key-id",
                    "x-timestamp"
                  ],
                  requiredCoveredComponents: ["@method", "@path", "x-siwa-receipt"],
                  coveredComponents: ["@method", "@path", "x-siwa-receipt"]
                }
              })

            401 ->
              ~s({"ok":false,"code":"receipt_invalid"})

            422 ->
              ~s({"ok":false,"code":"http_signature_input_invalid"})

            _ ->
              ~s({"ok":false,"code":"internal_error"})
          end

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(status, body)

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, ~s({"ok":false}))
    end
  end
end
