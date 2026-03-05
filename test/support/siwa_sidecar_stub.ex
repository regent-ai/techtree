defmodule TechTreeWeb.TestSupport.SiwaSidecarStub do
  @moduledoc false

  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case {conn.method, conn.request_path} do
      {"POST", "/v1/http-verify"} ->
        {:ok, raw_body, conn} = read_body(conn)

        parsed_body =
          case Jason.decode(raw_body) do
            {:ok, decoded} -> decoded
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
            200 -> ~s({"ok":true})
            _ -> ~s({"ok":false})
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
