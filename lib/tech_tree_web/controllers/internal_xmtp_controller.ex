defmodule TechTreeWeb.InternalXmtpController do
  use TechTreeWeb, :controller

  alias TechTreeWeb.ApiError
  alias TechTree.XMTPMirror

  @spec show_room(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show_room(conn, %{"room_key" => room_key}) do
    room =
      room_key
      |> XMTPMirror.get_room_by_key()
      |> encode_room()

    json(conn, %{data: room})
  end

  @spec upsert_room(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def upsert_room(conn, params) do
    with {:ok, room} <-
           XMTPMirror.upsert_room(%{
             room_key: params["room_key"],
             xmtp_group_id: params["xmtp_group_id"],
             name: params["name"],
             status: params["status"] || "active"
           }) do
      json(conn, %{data: encode_room(room)})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset_error(conn, "room_upsert_failed", changeset)
    end
  end

  @spec upsert_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def upsert_message(conn, params) do
    with {:ok, room} <- fetch_room(params["room_key"]),
         {:ok, message} <-
           XMTPMirror.upsert_message(%{
             room_id: room.id,
             xmtp_message_id: params["xmtp_message_id"],
             sender_inbox_id: params["sender_inbox_id"],
             sender_wallet_address: params["sender_wallet_address"],
             sender_label: params["sender_label"],
             sender_type: params["sender_type"],
             body: params["body"],
             sent_at: params["sent_at"],
             raw_payload: params["raw_payload"] || %{},
             moderation_state: params["moderation_state"] || "visible"
           }) do
      json(conn, %{data: %{id: message.id}})
    else
      {:error, :room_not_found} ->
        render_unprocessable(conn, "room_not_found")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset_error(conn, "message_upsert_failed", changeset)
    end
  end

  @spec lease_command(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def lease_command(conn, %{"room_key" => room_key}) do
    data =
      case XMTPMirror.lease_next_command(room_key) do
        nil ->
          nil

        command ->
          %{
            id: command.id,
            op: command.op,
            xmtp_inbox_id: command.xmtp_inbox_id
          }
      end

    json(conn, %{data: data})
  end

  def lease_command(conn, _params) do
    render_unprocessable(conn, "room_key_required")
  end

  @spec complete_command(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def complete_command(conn, %{"id" => id}) do
    with_existing_command(conn, fn -> XMTPMirror.complete_command(id) end)
  end

  @spec fail_command(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def fail_command(conn, %{"id" => id} = params) do
    error_message =
      params["error"]
      |> normalize_error_message()

    with_existing_command(conn, fn -> XMTPMirror.fail_command(id, error_message) end)
  end

  @spec fetch_room(String.t() | nil) :: {:ok, TechTree.XMTPMirror.XmtpRoom.t()} | {:error, :room_not_found}
  defp fetch_room(room_key) when is_binary(room_key) do
    case XMTPMirror.get_room_by_key(room_key) do
      nil -> {:error, :room_not_found}
      room -> {:ok, room}
    end
  end

  defp fetch_room(_room_key), do: {:error, :room_not_found}

  @spec encode_room(TechTree.XMTPMirror.XmtpRoom.t() | nil) :: map() | nil
  defp encode_room(nil), do: nil

  defp encode_room(room) do
    %{
      id: room.id,
      room_key: room.room_key,
      xmtp_group_id: room.xmtp_group_id,
      name: room.name,
      status: room.status
    }
  end

  @spec render_unprocessable(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  defp render_unprocessable(conn, code) do
    ApiError.render(conn, :unprocessable_entity, %{code: code})
  end

  @spec render_changeset_error(Plug.Conn.t(), String.t(), Ecto.Changeset.t()) :: Plug.Conn.t()
  defp render_changeset_error(conn, code, changeset) do
    ApiError.render(conn, :unprocessable_entity, %{
      code: code,
      details: ApiError.translate_changeset(changeset)
    })
  end

  @spec with_existing_command(Plug.Conn.t(), (() -> :ok)) :: Plug.Conn.t()
  defp with_existing_command(conn, command_fun) when is_function(command_fun, 0) do
    :ok = command_fun.()
    json(conn, %{ok: true})
  rescue
    Ecto.NoResultsError -> ApiError.render(conn, :not_found, %{code: "command_not_found"})
  end

  @spec normalize_error_message(String.t() | nil) :: String.t()
  defp normalize_error_message(value) when is_binary(value) and value != "", do: value
  defp normalize_error_message(_value), do: "membership_command_failed"
end
