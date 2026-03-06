defmodule TechTreeWeb.InternalXmtpController do
  use TechTreeWeb, :controller

  alias TechTree.XMTPMirror
  alias TechTreeWeb.ApiError
  alias TechTreeWeb.ControllerHelpers

  @spec list_shards(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list_shards(conn, _params) do
    json(conn, %{data: XMTPMirror.list_shards()})
  end

  @spec ensure_room(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ensure_room(conn, params) do
    room_attrs =
      %{
        room_key: params["room_key"],
        xmtp_group_id: params["xmtp_group_id"],
        name: params["name"],
        status: params["status"] || "active",
        presence_ttl_seconds: params["presence_ttl_seconds"]
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    with {:ok, room} <-
           XMTPMirror.ensure_room(room_attrs) do
      json(conn, %{data: encode_room(room)})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset_error(conn, "room_ensure_failed", changeset)
    end
  end

  @spec ingest_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ingest_message(conn, params) do
    with {:ok, room} <- fetch_room(params["room_key"]),
         {:ok, message} <-
           XMTPMirror.ingest_message(%{
             room_id: room.id,
             xmtp_message_id: params["xmtp_message_id"],
             sender_inbox_id: params["sender_inbox_id"],
             sender_wallet_address: params["sender_wallet_address"],
             sender_label: params["sender_label"],
             sender_type: params["sender_type"],
             body: params["body"],
             sent_at: params["sent_at"],
             raw_payload: params["raw_payload"] || %{},
             moderation_state: params["moderation_state"] || "visible",
             reply_to_message_id: params["reply_to_message_id"],
             reactions: params["reactions"]
           }) do
      json(conn, %{data: %{id: message.id}})
    else
      {:error, :room_not_found} ->
        render_unprocessable(conn, "room_not_found")

      {:error, :invalid_reply_to_message} ->
        render_unprocessable(conn, "invalid_reply_to_message")

      {:error, :invalid_reactions} ->
        render_unprocessable(conn, "invalid_reactions")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset_error(conn, "message_ingest_failed", changeset)
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

  @spec resolve_command(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def resolve_command(conn, %{"id" => id} = params) do
    case ControllerHelpers.parse_positive_int(id) do
      {:ok, normalized_id} ->
        with_existing_command(conn, fn ->
          case XMTPMirror.resolve_command(normalized_id, %{
                 status: params["status"],
                 error: params["error"]
               }) do
            :ok -> :ok
            {:error, :invalid_resolution_status} -> {:error, :invalid_resolution_status}
          end
        end)

      {:error, _reason} ->
        render_unprocessable(conn, "invalid_command_id")
    end
  end

  @spec fetch_room(String.t() | nil) ::
          {:ok, TechTree.XMTPMirror.XmtpRoom.t()} | {:error, :room_not_found}
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
      status: room.status,
      presence_ttl_seconds: room.presence_ttl_seconds
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

  @spec with_existing_command(Plug.Conn.t(), (-> :ok | {:error, :invalid_resolution_status})) ::
          Plug.Conn.t()
  defp with_existing_command(conn, command_fun) when is_function(command_fun, 0) do
    case command_fun.() do
      :ok ->
        json(conn, %{ok: true})

      {:error, :invalid_resolution_status} ->
        render_unprocessable(conn, "command_resolution_status_invalid")
    end
  rescue
    Ecto.NoResultsError -> ApiError.render(conn, :not_found, %{code: "command_not_found"})
  end
end