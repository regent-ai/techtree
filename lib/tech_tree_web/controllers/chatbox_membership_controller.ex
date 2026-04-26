defmodule TechTreeWeb.ChatboxMembershipController do
  use TechTreeWeb, :controller

  alias TechTree.XMTPMirror
  alias TechTreeWeb.ApiError

  @spec membership(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def membership(conn, _params) do
    human = conn.assigns.current_human
    json(conn, %{data: XMTPMirror.membership_for(human)})
  end

  @spec request_join(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def request_join(conn, params) do
    human = conn.assigns.current_human

    case XMTPMirror.request_join(human, params) do
      {:ok, result} ->
        json(conn, %{data: result})

      {:error, :human_banned} ->
        ApiError.render(conn, :forbidden, %{
          code: "human_banned",
          message: "banned humans cannot join chatbox"
        })

      {:error, :room_not_found} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "room_not_found",
          message: "requested chatbox room not found"
        })

      {:error, :xmtp_identity_required} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "chat_identity_required",
          message: "finish secure room setup before you join the public room"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "membership_request_failed",
          details: ApiError.translate_changeset(changeset)
        })
    end
  end

  @spec heartbeat(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def heartbeat(conn, params) do
    human = conn.assigns.current_human

    case XMTPMirror.heartbeat_presence(human, params) do
      {:ok, result} ->
        json(conn, %{data: result})

      {:error, :human_banned} ->
        ApiError.render(conn, :forbidden, %{
          code: "human_banned",
          message: "banned humans cannot join chatbox"
        })

      {:error, :room_not_found} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "room_not_found",
          message: "requested chatbox room not found"
        })

      {:error, :xmtp_identity_required} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "chat_identity_required",
          message: "finish secure room setup before you join the public room"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "membership_heartbeat_failed",
          details: ApiError.translate_changeset(changeset)
        })
    end
  end
end
