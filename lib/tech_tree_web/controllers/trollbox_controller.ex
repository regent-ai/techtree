defmodule TechTreeWeb.TrollboxController do
  use TechTreeWeb, :controller

  alias TechTree.RateLimit
  alias TechTree.XMTPMirror
  alias TechTree.XMTPMirror.{XmtpMessage, XmtpRoom}
  alias TechTreeWeb.ApiError

  @canonical_room_key "public-trollbox"

  @spec shards(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def shards(conn, _params) do
    json(conn, %{data: XMTPMirror.list_shards()})
  end

  @spec messages(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def messages(conn, params) do
    room_key = room_key_from_params(params)

    messages =
      params
      |> XMTPMirror.list_public_messages()
      |> Enum.map(&encode_message(&1, room_key))

    json(conn, %{data: messages})
  end

  @spec request_join(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def request_join(conn, params) do
    human = conn.assigns.current_human

    case XMTPMirror.request_join(human, params) do
      {:ok, request} ->
        json(conn, %{data: request})

      {:error, :room_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "room_unavailable"})

      {:error, :xmtp_inbox_already_bound} ->
        ApiError.render(conn, :conflict, %{
          code: "xmtp_inbox_already_bound",
          message: "xmtp_inbox_id already bound to this user"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "join_request_invalid",
          details: ApiError.translate_changeset(changeset)
        })
    end
  end

  @spec request_leave(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def request_leave(conn, params) do
    human = conn.assigns.current_human

    case XMTPMirror.request_leave(human, params) do
      {:ok, request} ->
        json(conn, %{data: request})

      {:error, :room_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "room_unavailable"})

      {:error, :xmtp_inbox_already_bound} ->
        ApiError.render(conn, :conflict, %{
          code: "xmtp_inbox_already_bound",
          message: "xmtp_inbox_id already bound to this user"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "leave_request_invalid",
          details: ApiError.translate_changeset(changeset)
        })
    end
  end

  @spec membership(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def membership(conn, params) do
    human = conn.assigns.current_human
    status = XMTPMirror.membership_for(human, params)
    json(conn, %{data: status})
  end

  @spec heartbeat(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def heartbeat(conn, params) do
    human = conn.assigns.current_human

    case XMTPMirror.heartbeat_presence(human, params) do
      {:ok, heartbeat} ->
        json(conn, %{data: heartbeat})

      {:error, :membership_required} ->
        ApiError.render(conn, :forbidden, %{
          code: "membership_required",
          message: "join trollbox before sending heartbeat"
        })

      {:error, :room_unavailable} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "room_unavailable",
          message: "trollbox room unavailable"
        })

      {:error, :missing_inbox_id} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "missing_inbox_id",
          message: "xmtp_inbox_id required"
        })

      {:error, :xmtp_inbox_already_bound} ->
        ApiError.render(conn, :conflict, %{
          code: "xmtp_inbox_already_bound",
          message: "xmtp_inbox_id already bound to this user"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "heartbeat_invalid",
          details: ApiError.translate_changeset(changeset)
        })
    end
  end

  @spec create_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_message(conn, params) do
    human = conn.assigns.current_human
    identity_key = "human:#{human.id}"
    room_key = room_key_from_params(params)

    with :ok <- RateLimit.check_trollbox_post!(identity_key),
         {:ok, message} <- XMTPMirror.create_human_message(human, params) do
      conn
      |> put_status(:accepted)
      |> json(%{data: encode_message(message, room_key)})
    else
      {:error, :rate_limited} ->
        ApiError.render(conn, :too_many_requests, %{
          code: "rate_limited",
          message: "trollbox post rate limit reached"
        })

      {:error, :membership_required} ->
        ApiError.render(conn, :forbidden, %{
          code: "membership_required",
          message: "join trollbox before posting"
        })

      {:error, :room_unavailable} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "room_unavailable",
          message: "trollbox room unavailable"
        })

      {:error, :missing_inbox_id} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "missing_inbox_id",
          message: "xmtp_inbox_id required"
        })

      {:error, :body_required} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "body_required",
          message: "message body required"
        })

      {:error, :body_too_long} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "body_too_long",
          message: "message body exceeds maximum length"
        })

      {:error, :invalid_reply_to_message} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "invalid_reply_to_message",
          message: "reply target not found for this room"
        })

      {:error, :invalid_reactions} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "invalid_reactions",
          message: "reactions payload is invalid"
        })

      {:error, :xmtp_inbox_already_bound} ->
        ApiError.render(conn, :conflict, %{
          code: "xmtp_inbox_already_bound",
          message: "xmtp_inbox_id already bound to this user"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "message_create_failed",
          details: ApiError.translate_changeset(changeset)
        })
    end
  end

  @spec react_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def react_message(conn, %{"id" => message_id} = params) do
    human = conn.assigns.current_human

    case XMTPMirror.react_to_message(human, message_id, params) do
      {:ok, message} ->
        json(conn, %{data: encode_message(message, room_key_from_params(params))})

      {:error, :membership_required} ->
        ApiError.render(conn, :forbidden, %{
          code: "membership_required",
          message: "join trollbox before reacting"
        })

      {:error, :message_not_found} ->
        ApiError.render(conn, :not_found, %{
          code: "message_not_found",
          message: "message not found"
        })

      {:error, :invalid_reaction_emoji} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "invalid_reaction_emoji",
          message: "reaction emoji is invalid"
        })

      {:error, :invalid_reaction_operation} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "invalid_reaction_operation",
          message: "reaction operation is invalid"
        })

      {:error, :xmtp_inbox_already_bound} ->
        ApiError.render(conn, :conflict, %{
          code: "xmtp_inbox_already_bound",
          message: "xmtp_inbox_id already bound to this user"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "reaction_update_failed",
          details: ApiError.translate_changeset(changeset)
        })
    end
  end

  @spec room_key_from_params(map()) :: String.t()
  defp room_key_from_params(params) do
    params
    |> Map.get(
      "room_key",
      Map.get(params, :room_key, Map.get(params, "shard_key", Map.get(params, :shard_key)))
    )
    |> case do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> @canonical_room_key
          normalized -> normalized
        end

      _ ->
        @canonical_room_key
    end
  end

  @spec encode_message(XmtpMessage.t(), String.t()) :: map()
  defp encode_message(%XmtpMessage{} = message, fallback_room_key) do
    room_key =
      case message.room do
        %XmtpRoom{room_key: value} when is_binary(value) and value != "" -> value
        _ -> fallback_room_key
      end

    %{
      id: message.id,
      room_id: message.room_id,
      room_key: room_key,
      shard_key: room_key,
      xmtp_message_id: message.xmtp_message_id,
      sender_inbox_id: message.sender_inbox_id,
      sender_wallet_address: message.sender_wallet_address,
      sender_label: message.sender_label,
      sender_type:
        if(is_atom(message.sender_type),
          do: Atom.to_string(message.sender_type),
          else: message.sender_type
        ),
      body: message.body,
      sent_at: message.sent_at,
      moderation_state: message.moderation_state,
      reply_to_message_id: message.reply_to_message_id,
      reactions: message.reactions || %{},
      inserted_at: message.inserted_at
    }
  end
end
