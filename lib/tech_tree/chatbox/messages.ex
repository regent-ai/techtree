defmodule TechTree.Chatbox.Messages do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Accounts.HumanUser
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Chatbox.Actor
  alias TechTree.Chatbox.Message
  alias TechTree.Chatbox.Payload
  alias TechTree.Repo

  @type actor :: HumanUser.t() | AgentIdentity.t()

  @spec list_public_messages(map(), keyword()) :: %{
          messages: [Message.t()],
          next_cursor: integer() | nil
        }
  def list_public_messages(params, opts) when is_map(params) do
    default_room = Keyword.fetch!(opts, :default_room)
    default_limit = Keyword.fetch!(opts, :default_limit)
    max_limit = Keyword.fetch!(opts, :max_limit)

    limit = Payload.parse_limit(params, default_limit, max_limit)
    before_id = Payload.parse_before_id(params)
    room_id = Payload.normalize_room_param(params, default_room)

    messages =
      public_messages_query()
      |> where([m], m.room_id == ^room_id)
      |> maybe_filter_before(before_id)
      |> order_by([m], desc: m.inserted_at, desc: m.id)
      |> limit(^(limit + 1))
      |> Repo.all()

    {page, overflow} = Enum.split(messages, limit)

    %{
      messages: page,
      next_cursor: next_cursor(page, overflow)
    }
  end

  @spec create_message({:human | :agent, actor()}, map(), keyword()) ::
          {:ok, Message.t(), TechTree.Chatbox.create_status()}
          | {:error,
             :body_required
             | :body_too_long
             | :invalid_reply_to_message
             | :invalid_client_message_id
             | Ecto.Changeset.t()}
  def create_message({kind, actor}, attrs, opts) when is_map(attrs) do
    default_room = Keyword.fetch!(opts, :default_room)
    max_message_length = Keyword.fetch!(opts, :max_message_length)

    with {:ok, body} <- Payload.normalize_message_body(attrs, max_message_length),
         {:ok, client_message_id} <- Payload.normalize_client_message_id(attrs),
         {:ok, reply_to_message_id} <- validate_reply_to_message_id(attrs, default_room) do
      author_scope = Actor.author_scope(kind, actor)
      room_id = Payload.normalize_room_param(attrs, default_room)

      case find_message_by_client_message_id(author_scope, room_id, client_message_id) do
        %Message{} = existing ->
          {:ok, preload_message(existing), :existing}

        nil ->
          insert_message(
            kind,
            actor,
            author_scope,
            room_id,
            body,
            client_message_id,
            reply_to_message_id
          )
      end
    end
  end

  @spec update_visibility(integer() | String.t(), String.t()) ::
          {:ok, Message.t()} | {:error, :message_not_found}
  def update_visibility(id, moderation_state) do
    with {:ok, normalized_id} <- Payload.parse_message_id(id, :message_not_found),
         %Message{} = message <- Repo.get(Message, normalized_id),
         {:ok, updated} <-
           message
           |> Ecto.Changeset.change(moderation_state: moderation_state)
           |> Repo.update() do
      {:ok, preload_message(updated)}
    else
      nil -> {:error, :message_not_found}
      {:error, :message_not_found} = error -> error
    end
  end

  @spec fetch_public_message(integer()) :: {:ok, Message.t()} | {:error, :message_not_found}
  def fetch_public_message(message_id) when is_integer(message_id) do
    case public_messages_query() |> where([m], m.id == ^message_id) |> Repo.one() do
      %Message{} = message -> {:ok, message}
      nil -> {:error, :message_not_found}
    end
  end

  @spec ingest_transport_message(binary(), map(), keyword()) ::
          {:ok, String.t() | nil, Message.t()} | {:error, term()}
  def ingest_transport_message(topic, payload, opts) when is_binary(topic) and is_map(payload) do
    default_room = Keyword.fetch!(opts, :default_room)

    with :ok <- Payload.validate_transport_payload(topic, payload),
         {:ok, message} <- upsert_transport_message(topic, payload, default_room) do
      {:ok, Map.get(payload, "kind"), message}
    end
  end

  @spec preload_message(Message.t()) :: Message.t()
  def preload_message(%Message{} = message) do
    Repo.preload(message, [:author_human, :author_agent])
  end

  defp public_messages_query do
    public_messages_query(true)
  end

  defp public_messages_query(preload?) do
    Message
    |> join(:left, [m], h in assoc(m, :author_human))
    |> join(:left, [m, _h], a in assoc(m, :author_agent))
    |> where([m], m.moderation_state != "hidden")
    |> where(
      [m, h, _a],
      m.author_kind != :human or is_nil(m.author_human_id) or
        (not is_nil(h.id) and h.role != "banned")
    )
    |> where(
      [m, _h, a],
      m.author_kind != :agent or is_nil(m.author_agent_id) or
        (not is_nil(a.id) and a.status == "active")
    )
    |> maybe_preload_public_message_authors(preload?)
  end

  defp maybe_filter_before(query, nil), do: query
  defp maybe_filter_before(query, before_id), do: where(query, [m], m.id < ^before_id)

  defp next_cursor([], _overflow), do: nil
  defp next_cursor(_page, []), do: nil

  defp next_cursor(page, [_ | _]) do
    case List.last(page) do
      nil -> nil
      %Message{id: id} -> id
    end
  end

  defp find_message_by_client_message_id(_author_scope, _room_id, nil), do: nil

  defp find_message_by_client_message_id(author_scope, room_id, client_message_id) do
    Repo.get_by(Message,
      author_scope: author_scope,
      room_id: room_id,
      client_message_id: client_message_id
    )
  end

  defp insert_message(
         kind,
         actor,
         author_scope,
         room_id,
         body,
         client_message_id,
         reply_to_message_id
       ) do
    attrs =
      %{
        room_id: room_id,
        author_kind: kind,
        author_scope: author_scope,
        body: body,
        client_message_id: client_message_id,
        reply_to_message_id: reply_to_message_id,
        reply_to_transport_msg_id: reply_to_transport_msg_id(reply_to_message_id),
        moderation_state: "visible",
        reactions: %{},
        transport_msg_id: transport_message_id(author_scope, room_id, client_message_id),
        transport_topic: TechTree.P2P.Transport.topic_for_room(room_id),
        origin_node_id: TechTree.P2P.Transport.origin_node_id(),
        transport_payload: %{}
      }
      |> Actor.put_author_fields(kind, actor)

    case %Message{} |> Message.changeset(attrs) |> Repo.insert() do
      {:ok, message} ->
        {:ok, preload_message(message), :created}

      {:error, %Ecto.Changeset{} = changeset} ->
        case find_message_by_client_message_id(author_scope, room_id, client_message_id) do
          %Message{} = existing -> {:ok, preload_message(existing), :existing}
          nil -> {:error, changeset}
        end
    end
  end

  defp reply_to_transport_msg_id(nil), do: nil

  defp reply_to_transport_msg_id(reply_to_message_id) do
    case Repo.get(Message, reply_to_message_id) do
      %Message{transport_msg_id: transport_msg_id} -> transport_msg_id
      _ -> nil
    end
  end

  defp transport_message_id(author_scope, room_id, nil) do
    suffix = System.unique_integer([:positive, :monotonic])
    "chatbox:#{room_id}:#{author_scope}:#{suffix}"
  end

  defp transport_message_id(author_scope, room_id, client_message_id) do
    payload = "#{room_id}:#{author_scope}:#{client_message_id}"
    hash = :crypto.hash(:sha256, payload) |> Base.url_encode64(padding: false)
    "chatbox:#{hash}"
  end

  defp validate_reply_to_message_id(attrs, default_room) when is_map(attrs) do
    room_id = Payload.normalize_room_param(attrs, default_room)

    attrs
    |> Map.get("reply_to_message_id", Map.get(attrs, :reply_to_message_id))
    |> case do
      nil ->
        {:ok, nil}

      value ->
        with {:ok, reply_to_message_id} <-
               Payload.parse_message_id(value, :invalid_reply_to_message),
             true <-
               Repo.exists?(
                 from(
                   m in public_messages_query(false),
                   where: m.id == ^reply_to_message_id and m.room_id == ^room_id
                 )
               ) do
          {:ok, reply_to_message_id}
        else
          _ -> {:error, :invalid_reply_to_message}
        end
    end
  end

  defp upsert_transport_message(topic, payload, default_room) do
    transport_msg_id = payload["transport_msg_id"]
    actor = Map.get(payload, "actor", %{})
    room_id = Map.get(payload, "room_id") || default_room
    reply_to_transport_msg_id = Map.get(payload, "reply_to_transport_msg_id")

    attrs = %{
      room_id: room_id,
      author_kind: String.to_existing_atom(actor["type"]),
      author_scope: actor["id"] || actor["address"] || "remote:#{transport_msg_id}",
      author_transport_id: actor["id"],
      author_display_name_snapshot: actor["display_name"],
      author_label_snapshot: actor["label"],
      author_wallet_address_snapshot: actor["address"],
      body: payload["body"],
      client_message_id: payload["client_message_id"],
      reply_to_transport_msg_id: reply_to_transport_msg_id,
      reply_to_message_id: reply_to_message_id(reply_to_transport_msg_id),
      reactions: payload["reactions"] || %{},
      moderation_state: payload["moderation_state"] || "visible",
      transport_msg_id: transport_msg_id,
      transport_topic: topic,
      origin_peer_id: payload["origin_peer_id"],
      origin_node_id: payload["origin_node_id"],
      transport_payload: payload,
      inserted_at: Payload.parse_transport_datetime(payload["inserted_at"]),
      updated_at: Payload.parse_transport_datetime(payload["updated_at"]) || DateTime.utc_now()
    }

    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          body: attrs.body,
          reactions: attrs.reactions,
          moderation_state: attrs.moderation_state,
          reply_to_transport_msg_id: attrs.reply_to_transport_msg_id,
          reply_to_message_id: attrs.reply_to_message_id,
          origin_peer_id: attrs.origin_peer_id,
          origin_node_id: attrs.origin_node_id,
          transport_topic: attrs.transport_topic,
          transport_payload: attrs.transport_payload,
          updated_at: attrs.updated_at
        ]
      ],
      conflict_target: [:transport_msg_id],
      returning: true
    )
    |> case do
      {:ok, message} -> {:ok, preload_message(message)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp reply_to_message_id(value) when is_binary(value) do
    case Repo.get_by(Message, transport_msg_id: value) do
      %Message{id: id} -> id
      _ -> nil
    end
  end

  defp reply_to_message_id(_value), do: nil

  defp maybe_preload_public_message_authors(query, true) do
    preload(query, [_m, h, a], author_human: h, author_agent: a)
  end

  defp maybe_preload_public_message_authors(query, false), do: query
end
