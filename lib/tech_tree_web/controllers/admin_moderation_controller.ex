defmodule TechTreeWeb.AdminModerationController do
  use TechTreeWeb, :controller

  alias TechTree.Moderation
  alias TechTree.XMTPMirror

  @spec hide_node(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def hide_node(conn, %{"id" => id} = params) do
    admin = conn.assigns.current_human
    :ok = Moderation.hide_node(id, admin, params["reason"])
    json(conn, %{ok: true})
  end

  @spec hide_comment(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def hide_comment(conn, %{"id" => id} = params) do
    admin = conn.assigns.current_human
    :ok = Moderation.hide_comment(id, admin, params["reason"])
    json(conn, %{ok: true})
  end

  @spec hide_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def hide_message(conn, %{"id" => id} = params) do
    admin = conn.assigns.current_human
    :ok = Moderation.hide_trollbox_message(id, admin, params["reason"])
    json(conn, %{ok: true})
  end

  @spec ban_agent(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ban_agent(conn, %{"id" => id} = params) do
    admin = conn.assigns.current_human
    :ok = Moderation.ban_agent(id, admin, params["reason"])
    json(conn, %{ok: true})
  end

  @spec ban_human(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ban_human(conn, %{"id" => id} = params) do
    admin = conn.assigns.current_human
    :ok = Moderation.ban_human(id, admin, params["reason"])
    json(conn, %{ok: true})
  end

  @spec add_trollbox_member(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def add_trollbox_member(conn, %{"human_id" => human_id}) do
    :ok = XMTPMirror.add_human_to_canonical_room(human_id)
    json(conn, %{ok: true})
  end

  @spec remove_trollbox_member(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def remove_trollbox_member(conn, %{"human_id" => human_id}) do
    :ok = XMTPMirror.remove_human_from_canonical_room(human_id)
    json(conn, %{ok: true})
  end
end
