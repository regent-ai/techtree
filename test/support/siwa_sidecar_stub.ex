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
        trusted_headers = trusted_call_headers(conn)

        parsed_body =
          case Jason.decode(raw_body) do
            {:ok, decoded} -> decoded
            _ -> %{"body" => raw_body}
          end

        trusted_result = verify_trusted_call(conn, raw_body, trusted_headers)

        configured_status =
          Agent.get_and_update(TechTreeWeb.TestSupport.SiwaSidecarState, fn state ->
            normalized_state =
              case state do
                %{status: current_status} = map when is_integer(current_status) -> map
                value when is_integer(value) -> %{status: value}
                _ -> %{status: 200}
              end

            updated_state =
              normalized_state
              |> Map.put(:last_request, parsed_body)
              |> Map.put(:last_trusted_headers, trusted_headers)

            {Map.get(normalized_state, :status, 200), updated_state}
          end)

        status =
          case trusted_result do
            :ok -> configured_status
            {:error, _reason} -> 401
          end

        body =
          case {trusted_result, status} do
            {{:error, reason}, 401} ->
              Jason.encode!(%{ok: false, code: Atom.to_string(reason)})

            {:ok, 200} ->
              headers = Map.get(parsed_body, "headers", %{})

              Jason.encode!(%{
                ok: true,
                code: "http_envelope_valid",
                data: %{
                  verified: true,
                  walletAddress: Map.get(headers, "x-agent-wallet-address"),
                  chainId: String.to_integer(Map.get(headers, "x-agent-chain-id", "0")),
                  keyId: Map.get(headers, "x-key-id"),
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

            {:ok, 401} ->
              ~s({"ok":false,"code":"receipt_invalid"})

            {:ok, 422} ->
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

  defp trusted_call_headers(conn) do
    %{
      "x-sidecar-key-id" => conn |> get_req_header("x-sidecar-key-id") |> List.first(),
      "x-sidecar-timestamp" => conn |> get_req_header("x-sidecar-timestamp") |> List.first(),
      "x-sidecar-signature" => conn |> get_req_header("x-sidecar-signature") |> List.first()
    }
  end

  defp verify_trusted_call(conn, raw_body, trusted_headers) do
    with key_id when is_binary(key_id) <- trusted_headers["x-sidecar-key-id"],
         timestamp when is_binary(timestamp) <- trusted_headers["x-sidecar-timestamp"],
         signature when is_binary(signature) <- trusted_headers["x-sidecar-signature"],
         :ok <- verify_key_id(key_id),
         :ok <- verify_timestamp(timestamp),
         :ok <- verify_signature(conn.method, conn.request_path, timestamp, raw_body, signature) do
      :ok
    else
      nil -> {:error, :auth_headers_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_key_id("sidecar-internal-v1"), do: :ok
  defp verify_key_id(_key_id), do: {:error, :auth_key_id_invalid}

  defp verify_timestamp(timestamp) do
    case Integer.parse(timestamp) do
      {parsed, ""} when parsed > 0 -> :ok
      _ -> {:error, :auth_timestamp_invalid}
    end
  end

  defp verify_signature(method, path, timestamp, raw_body, signature) do
    secret =
      Application.get_env(:tech_tree, :siwa, [])
      |> Keyword.fetch!(:shared_secret)

    expected =
      "sha256=" <>
        (:crypto.mac(:hmac, :sha256, secret, "#{method}\n#{path}\n#{timestamp}\n#{raw_body}")
         |> Base.encode16(case: :lower))

    if Plug.Crypto.secure_compare(signature, expected) do
      :ok
    else
      {:error, :auth_signature_mismatch}
    end
  end
end
