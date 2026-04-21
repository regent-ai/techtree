defmodule TechTreeWeb.TestSupport.SiwaSidecarStub do
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
            {:ok, decoded} -> Map.put(decoded, "_siwa_audience", audience)
            _ -> %{"raw_body" => raw_body}
          end

        status =
          Agent.get_and_update(TechTreeWeb.TestSupport.SiwaSidecarState, fn state ->
            normalized_state =
              case state do
                %{status: current_status} = map when is_integer(current_status) -> map
                value when is_integer(value) -> %{status: value}
                _ -> %{status: 200}
              end

            updated_state = Map.put(normalized_state, :last_request, parsed_body)
            {Map.get(normalized_state, :status, 200), updated_state}
          end)

        body =
          case status do
            200 ->
              headers = Map.get(parsed_body, "headers", %{})

              Jason.encode!(%{
                ok: true,
                code: "http_envelope_valid",
                data: %{
                  agent_claims: %{
                    wallet_address: Map.get(headers, "x-agent-wallet-address"),
                    chain_id: String.to_integer(Map.get(headers, "x-agent-chain-id", "0")),
                    registry_address: Map.get(headers, "x-agent-registry-address"),
                    token_id: Map.get(headers, "x-agent-token-id"),
                    label: Map.get(headers, "x-agent-label")
                  },
                  audience: Map.get(parsed_body, "audience")
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
