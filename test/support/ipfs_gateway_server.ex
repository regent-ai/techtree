defmodule TechTree.TestIpfsGatewayServer do
  @moduledoc false

  def child_spec({responses, port}) when is_map(responses) and is_integer(port) do
    %{
      id: {__MODULE__, port},
      start: {__MODULE__, :start_link, [responses, port]}
    }
  end

  def start_link(responses, port) do
    Bandit.start_link(
      plug: {__MODULE__, responses},
      ip: {127, 0, 0, 1},
      port: port
    )
  end

  def init(responses), do: responses

  def call(conn, responses) do
    request_path = String.trim_leading(conn.request_path, "/")

    case Map.fetch(responses, request_path) do
      {:ok, body} ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(body))

      :error ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "not_found"}))
    end
  end
end
