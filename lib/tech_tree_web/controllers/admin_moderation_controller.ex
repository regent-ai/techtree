defmodule TechTreeWeb.AdminModerationController do
  use TechTreeWeb, :controller

  alias TechTree.Moderation
  alias TechTree.XMTPMirror
  alias TechTreeWeb.ApiError
  alias TechTreeWeb.ControllerHelpers

  @spec hide_node(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def hide_node(conn, %{"id" => id} = params) do
    with_admin_action(conn, id, "invalid_node_id", "node_not_found", fn normalized_id, admin ->
      Moderation.hide_node(normalized_id, admin, params["reason"])
    end)
  end

  @spec hide_comment(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def hide_comment(conn, %{"id" => id} = params) do
    with_admin_action(conn, id, "invalid_comment_id", "comment_not_found", fn normalized_id,
                                                                              admin ->
      Moderation.hide_comment(normalized_id, admin, params["reason"])
    end)
  end

  @spec hide_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def hide_message(conn, %{"id" => id} = params) do
    with_admin_action(conn, id, "invalid_message_id", "message_not_found", fn normalized_id,
                                                                              admin ->
      Moderation.hide_trollbox_message(normalized_id, admin, params["reason"])
    end)
  end

  @spec unhide_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def unhide_message(conn, %{"id" => id} = params) do
    with_admin_action(conn, id, "invalid_message_id", "message_not_found", fn normalized_id,
                                                                              admin ->
      Moderation.unhide_trollbox_message(normalized_id, admin, params["reason"])
    end)
  end

  @spec ban_agent(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ban_agent(conn, %{"id" => id} = params) do
    with_admin_action(conn, id, "invalid_agent_id", "agent_not_found", fn normalized_id, admin ->
      Moderation.ban_agent(normalized_id, admin, params["reason"])
    end)
  end

  @spec unban_agent(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def unban_agent(conn, %{"id" => id} = params) do
    with_admin_action(conn, id, "invalid_agent_id", "agent_not_found", fn normalized_id, admin ->
      Moderation.unban_agent(normalized_id, admin, params["reason"])
    end)
  end

  @spec ban_human(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ban_human(conn, %{"id" => id} = params) do
    with_admin_action(conn, id, "invalid_human_id", "human_not_found", fn normalized_id, admin ->
      Moderation.ban_human(normalized_id, admin, params["reason"])
    end)
  end

  @spec unban_human(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def unban_human(conn, %{"id" => id} = params) do
    with_admin_action(conn, id, "invalid_human_id", "human_not_found", fn normalized_id, admin ->
      Moderation.unban_human(normalized_id, admin, params["reason"])
    end)
  end

  @spec add_trollbox_member(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def add_trollbox_member(conn, %{"id" => id}) do
    with_admin_action(conn, id, "invalid_human_id", "human_not_found", fn normalized_id, _admin ->
      XMTPMirror.add_human_to_canonical_room(normalized_id)
    end)
  end

  @spec remove_trollbox_member(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def remove_trollbox_member(conn, %{"id" => id}) do
    with_admin_action(conn, id, "invalid_human_id", "human_not_found", fn normalized_id, _admin ->
      XMTPMirror.remove_human_from_canonical_room(normalized_id)
    end)
  end

  @spec with_admin_action(
          Plug.Conn.t(),
          term(),
          String.t(),
          String.t(),
          (integer(), TechTree.Accounts.HumanUser.t() -> :ok)
        ) :: Plug.Conn.t()
  defp with_admin_action(conn, raw_id, invalid_code, not_found_code, action_fun)
       when is_function(action_fun, 2) do
    case ControllerHelpers.parse_positive_int(raw_id) do
      {:ok, normalized_id} ->
        admin = conn.assigns.current_human
        action_fun.(normalized_id, admin)
        json(conn, %{ok: true})

      {:error, _reason} ->
        ApiError.render(conn, :unprocessable_entity, %{code: invalid_code})
    end
  rescue
    Ecto.NoResultsError -> ApiError.render(conn, :not_found, %{code: not_found_code})
  end
end
