defmodule TechTree.XMTPMirror.Messages do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Accounts.HumanUser
  alias TechTree.PublicEvents
  alias TechTree.QueryHelpers
  alias TechTree.Repo
  alias TechTree.XMTPMirror.Membership
  alias TechTree.XMTPMirror.Rooms
  alias TechTree.XMTPMirror.XmtpMessage

  @spec ingest_message(map()) ::
          {:ok, XmtpMessage.t()}
          | {:error,
             :room_not_found | :invalid_reply_to_message | :invalid_reactions | Ecto.Changeset.t()}
  def ingest_message(attrs) when is_map(attrs) do
    with {:ok, room} <- Rooms.resolve_message_room(attrs),
         :ok <- validate_reaction_payload(attrs),
         :ok <- validate_reply_to_message(attrs) do
      message_attrs =
        attrs
        |> normalize_message_attrs(room)
        |> Map.put(:room_id, room.id)

      %XmtpMessage{}
      |> XmtpMessage.changeset(message_attrs)
      |> Repo.insert()
      |> case do
        {:ok, %XmtpMessage{} = message} ->
          maybe_broadcast_public_message(message, room)
          {:ok, message}

        {:error, %Ecto.Changeset{errors: [xmtp_message_id: {"has already been taken", _}]}} ->
          case Repo.get_by(XmtpMessage, xmtp_message_id: message_attrs.xmtp_message_id) do
            %XmtpMessage{} = message -> {:ok, message}
            nil -> {:error, :room_not_found}
          end

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @spec create_human_message(HumanUser.t(), map()) ::
          {:ok, XmtpMessage.t()}
          | {:error,
             :room_not_found
             | :xmtp_identity_required
             | :xmtp_membership_required
             | Ecto.Changeset.t()}
  def create_human_message(%HumanUser{} = human, attrs) when is_map(attrs) do
    with {:ok, inbox_id} <- Membership.require_human_inbox_id(human),
         {:ok, room} <- Rooms.resolve_message_room(attrs),
         :ok <- require_joined_room(human, room) do
      message_id =
        Rooms.value_for(attrs, "xmtp_message_id") ||
          "xmtp-#{room.id}-#{human.id}-#{System.unique_integer([:positive, :monotonic])}"

      message_attrs = %{
        room_id: room.id,
        xmtp_message_id: message_id,
        sender_inbox_id: inbox_id,
        sender_wallet_address: human.wallet_address,
        sender_label: human.display_name,
        sender_type: :human,
        body: Rooms.value_for(attrs, "body") || "",
        sent_at: normalize_sent_at(Rooms.value_for(attrs, "sent_at")),
        raw_payload: Rooms.value_for(attrs, "raw_payload") || %{},
        moderation_state: Rooms.value_for(attrs, "moderation_state") || "visible",
        reply_to_message_id: Rooms.value_for(attrs, "reply_to_message_id"),
        reactions: Rooms.value_for(attrs, "reactions") || %{}
      }

      %XmtpMessage{}
      |> XmtpMessage.changeset(message_attrs)
      |> Repo.insert()
      |> case do
        {:ok, %XmtpMessage{} = message} ->
          maybe_broadcast_public_message(message, room)
          {:ok, message}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @spec list_public_messages(map()) :: [XmtpMessage.t()]
  def list_public_messages(attrs \\ %{}) when is_map(attrs) do
    case Rooms.resolve_message_room(attrs) do
      {:ok, room} ->
        XmtpMessage
        |> join(:left, [m], h in HumanUser,
          on:
            fragment("lower(?)", h.wallet_address) ==
              fragment("lower(?)", m.sender_wallet_address)
        )
        |> where([m], m.room_id == ^room.id and m.moderation_state == "visible")
        |> where([m, h], m.sender_type != :human or is_nil(h.id) or h.role != "banned")
        |> order_by([m], desc: m.sent_at, desc: m.id)
        |> limit(^QueryHelpers.parse_limit(attrs, 50))
        |> Repo.all()

      {:error, :room_not_found} ->
        []
    end
  end

  defp normalize_message_attrs(attrs, room) do
    %{
      room_id: room.id,
      xmtp_message_id: Rooms.value_for(attrs, "xmtp_message_id"),
      sender_inbox_id: Rooms.value_for(attrs, "sender_inbox_id"),
      sender_wallet_address: Rooms.value_for(attrs, "sender_wallet_address"),
      sender_label: Rooms.value_for(attrs, "sender_label"),
      sender_type: Rooms.value_for(attrs, "sender_type") || :human,
      body: Rooms.value_for(attrs, "body"),
      sent_at: normalize_sent_at(Rooms.value_for(attrs, "sent_at")),
      raw_payload: Rooms.value_for(attrs, "raw_payload") || %{},
      moderation_state: Rooms.value_for(attrs, "moderation_state") || "visible",
      reply_to_message_id: Rooms.value_for(attrs, "reply_to_message_id"),
      reactions: Rooms.value_for(attrs, "reactions") || %{}
    }
  end

  defp require_joined_room(%HumanUser{} = human, room) do
    if Membership.joined?(human, room), do: :ok, else: {:error, :xmtp_membership_required}
  end

  defp validate_reply_to_message(attrs) do
    case Rooms.value_for(attrs, "reply_to_message_id") do
      nil ->
        :ok

      reply_to_id when is_integer(reply_to_id) ->
        if Repo.get(XmtpMessage, reply_to_id), do: :ok, else: {:error, :invalid_reply_to_message}

      reply_to_id when is_binary(reply_to_id) ->
        case Integer.parse(String.trim(reply_to_id)) do
          {id, ""} when id > 0 ->
            if Repo.get(XmtpMessage, id), do: :ok, else: {:error, :invalid_reply_to_message}

          _ ->
            {:error, :invalid_reply_to_message}
        end

      _ ->
        {:error, :invalid_reply_to_message}
    end
  end

  defp validate_reaction_payload(attrs) do
    case Rooms.value_for(attrs, "reactions") do
      nil -> :ok
      reactions when is_map(reactions) -> :ok
      _ -> {:error, :invalid_reactions}
    end
  end

  defp normalize_sent_at(%DateTime{} = dt), do: dt

  defp normalize_sent_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp normalize_sent_at(_value), do: DateTime.utc_now()

  defp maybe_broadcast_public_message(%XmtpMessage{} = message, room) do
    if Rooms.public_room?(room) do
      PublicEvents.broadcast_xmtp_room_message(message, room.room_key)
    end
  end
end
