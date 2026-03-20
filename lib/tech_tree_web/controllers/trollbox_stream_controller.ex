defmodule TechTreeWeb.TrollboxStreamController do
  @moduledoc false
  use TechTreeWeb, :controller

  alias TechTree.Trollbox
  alias TechTreeWeb.ControllerHelpers

  @heartbeat_ms 15_000

  def index(conn, params) do
    room_id =
      case params["room"] do
        "agent" ->
          agent = ControllerHelpers.ensure_current_agent(conn)
          "agent:#{agent.id}"

        _ ->
          "global"
      end

    conn =
      conn
      |> put_resp_content_type("application/x-ndjson")
      |> send_chunked(:ok)

    Phoenix.PubSub.subscribe(TechTree.PubSub, Trollbox.relay_topic())
    stream_loop(conn, room_id)
  end

  defp stream_loop(conn, room_id) do
    receive do
      {:trollbox_event, %{message: %{"room_id" => ^room_id}} = envelope} ->
        case chunk(conn, Jason.encode!(envelope) <> "\n") do
          {:ok, conn} -> stream_loop(conn, room_id)
          {:error, _reason} -> conn
        end
    after
      @heartbeat_ms ->
        case chunk(conn, Jason.encode!(%{event: "heartbeat", room_id: room_id}) <> "\n") do
          {:ok, conn} -> stream_loop(conn, room_id)
          {:error, _reason} -> conn
        end
    end
  end
end
