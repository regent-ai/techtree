defmodule TechTreeWeb.AdminModerationController do
  use TechTreeWeb, :controller

  alias TechTree.Moderation
  alias TechTreeWeb.ApiError
  alias TechTreeWeb.ControllerHelpers

  @spec add_chatbox_member(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def add_chatbox_member(conn, %{"id" => id} = params) do
    with_member_action(conn, id, fn normalized_id, admin ->
      Moderation.apply_action(:add_chatbox_member, normalized_id, admin, params["reason"])
    end)
  end

  @spec remove_chatbox_member(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def remove_chatbox_member(conn, %{"id" => id} = params) do
    with_member_action(conn, id, fn normalized_id, admin ->
      Moderation.apply_action(:remove_chatbox_member, normalized_id, admin, params["reason"])
    end)
  end

  @spec with_member_action(
          Plug.Conn.t(),
          term(),
          (integer(), TechTree.Accounts.HumanUser.t() -> {:ok, atom()} | {:error, atom()})
        ) :: Plug.Conn.t()
  defp with_member_action(conn, raw_id, action_fun) when is_function(action_fun, 2) do
    case ControllerHelpers.parse_positive_int(raw_id) do
      {:ok, normalized_id} ->
        admin = conn.assigns.current_human

        case action_fun.(normalized_id, admin) do
          {:ok, status} when is_atom(status) ->
            json(conn, %{ok: true, data: %{status: Atom.to_string(status)}})

          {:error, :human_not_found} ->
            ApiError.render(conn, :not_found, %{code: "human_not_found"})

          {:error, :room_not_found} ->
            ApiError.render(conn, :unprocessable_entity, %{code: "room_not_found"})

          {:error, :xmtp_identity_required} ->
            ApiError.render(conn, :unprocessable_entity, %{code: "chat_identity_required"})

          {:error, :human_banned} ->
            ApiError.render(conn, :unprocessable_entity, %{code: "human_banned"})
        end

      {:error, _reason} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_human_id"})
    end
  rescue
    Ecto.NoResultsError -> ApiError.render(conn, :not_found, %{code: "human_not_found"})
  end
end
