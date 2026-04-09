defmodule TechTreeWeb.ChatboxStreamController do
  @moduledoc false
  use TechTreeWeb, :controller

  alias TechTree.Chatbox
  alias TechTreeWeb.ControllerHelpers

  @heartbeat_ms 15_000

  def index(conn, params) do
    case resolve_room_id(conn, params) do
      {:ok, room_id} ->
        conn =
          conn
          |> put_resp_content_type("application/x-ndjson")
          |> send_chunked(:ok)

        Phoenix.PubSub.subscribe(TechTree.PubSub, Chatbox.relay_topic())
        stream_loop(conn, room_id)

      {:error, :invalid_room} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "invalid_chatbox_room"}})
    end
  end

  defp stream_loop(conn, room_id) do
    receive do
      {:chatbox_event, %{message: %{"room_id" => ^room_id}} = envelope} ->
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

  defp resolve_room_id(conn, params) do
    requested_room =
      params["room"]
      |> case do
        value when is_binary(value) -> String.trim(value)
        _ -> nil
      end

    case {String.contains?(conn.request_path, "/v1/agent/"), requested_room} do
      {true, nil} ->
        agent = ControllerHelpers.ensure_current_agent(conn)
        {:ok, "agent:#{agent.id}"}

      {true, "agent"} ->
        agent = ControllerHelpers.ensure_current_agent(conn)
        {:ok, "agent:#{agent.id}"}

      {false, nil} ->
        {:ok, "global"}

      {false, "webapp"} ->
        {:ok, "global"}

      _ ->
        {:error, :invalid_room}
    end
  end
end
