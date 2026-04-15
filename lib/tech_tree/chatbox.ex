defmodule TechTree.Chatbox do
  @moduledoc false

  import Ecto.Query
  require Logger

  alias TechTree.Accounts.HumanUser
  alias TechTree.Agents.AgentIdentity
  alias TechTree.P2P.Transport
  alias TechTree.Repo
  alias TechTree.Chatbox.Message
  alias TechTree.Chatbox.MessageReaction
  alias TechTree.XmtpIdentity
  alias TechTreeWeb.{Endpoint, PublicEncoding}

  @global_room "global"
  @channel_topic "chatbox:public"
  @relay_topic "techtree.chatbox.public.v1"
  @default_limit 50
  @max_limit 100
  @max_message_length 2_000

  @type create_status :: :created | :existing
  @type actor :: HumanUser.t() | AgentIdentity.t()

  @spec channel_topic() :: String.t()
  def channel_topic, do: @channel_topic

  @spec relay_topic() :: String.t()
  def relay_topic, do: @relay_topic

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(TechTree.PubSub, @relay_topic)
  end

  @spec list_public_messages(map()) :: %{messages: [Message.t()], next_cursor: integer() | nil}
  def list_public_messages(params \\ %{}) when is_map(params) do
    limit = parse_limit(params)
    before_id = parse_before_id(params)
    room_id = normalize_room_param(params, @global_room)

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
      next_cursor:
        case {page, overflow} do
          {[], _} ->
            nil

          {_page, []} ->
            nil

          {page, [_ | _]} ->
            page
            |> List.last()
            |> case do
              nil -> nil
              %Message{id: id} -> id
            end
        end
    }
  end

  @spec create_human_message(HumanUser.t(), map()) ::
          {:ok, Message.t(), create_status()}
          | {:error,
             :human_banned
             | :xmtp_identity_required
             | :body_required
             | :body_too_long
             | :invalid_reply_to_message
             | :invalid_client_message_id
             | Ecto.Changeset.t()}
  def create_human_message(%HumanUser{role: "banned"}, _attrs), do: {:error, :human_banned}

  def create_human_message(%HumanUser{} = human, attrs) when is_map(attrs) do
    case XmtpIdentity.ready_inbox_id(human) do
      {:ok, _inbox_id} ->
        create_message({:human, human}, Map.put_new(attrs, :room_id, @global_room))

      {:error, :xmtp_identity_required} ->
        {:error, :xmtp_identity_required}

      {:error, :wallet_address_required} ->
        {:error, :xmtp_identity_required}
    end
  end

  @spec create_agent_message(AgentIdentity.t(), map()) ::
          {:ok, Message.t(), create_status()}
          | {:error,
             :agent_banned
             | :body_required
             | :body_too_long
             | :invalid_reply_to_message
             | :invalid_client_message_id
             | Ecto.Changeset.t()}
  def create_agent_message(%AgentIdentity{status: status}, _attrs)
      when status in ["banned", "inactive"] do
    {:error, :agent_banned}
  end

  def create_agent_message(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    create_message(
      {:agent, agent},
      Map.put_new(attrs, :room_id, normalize_agent_room(attrs, agent))
    )
  end

  @spec react_to_message(actor(), integer() | String.t(), map()) ::
          {:ok, Message.t()}
          | {:error,
             :human_banned
             | :agent_banned
             | :xmtp_identity_required
             | :message_not_found
             | :invalid_reaction_emoji
             | :invalid_reaction_operation
             | Ecto.Changeset.t()}
  def react_to_message(%HumanUser{role: "banned"}, _message_id, _attrs),
    do: {:error, :human_banned}

  def react_to_message(%AgentIdentity{status: status}, _message_id, _attrs)
      when status in ["banned", "inactive"] do
    {:error, :agent_banned}
  end

  def react_to_message(%HumanUser{} = human, message_id, attrs) when is_map(attrs) do
    with {:ok, _inbox_id} <- ready_reaction_identity(human),
         {:ok, normalized_message_id} <- parse_message_id(message_id, :message_not_found),
         {:ok, emoji} <- normalize_reaction_emoji(attrs),
         {:ok, operation} <- normalize_reaction_operation(attrs),
         {:ok, message} <- fetch_public_message(normalized_message_id) do
      update_message_reactions(message, actor_identity(human), emoji, operation)
    end
  end

  def react_to_message(actor, message_id, attrs) when is_map(attrs) do
    with {:ok, normalized_message_id} <- parse_message_id(message_id, :message_not_found),
         {:ok, emoji} <- normalize_reaction_emoji(attrs),
         {:ok, operation} <- normalize_reaction_operation(attrs),
         {:ok, message} <- fetch_public_message(normalized_message_id) do
      update_message_reactions(message, actor_identity(actor), emoji, operation)
    end
  end

  @spec hide_message(integer() | String.t()) :: {:ok, Message.t()}
  def hide_message(id) do
    case hide_message_if_present(id) do
      {:ok, message} -> {:ok, message}
      {:error, :message_not_found} -> raise Ecto.NoResultsError
    end
  end

  @spec unhide_message(integer() | String.t()) :: {:ok, Message.t()}
  def unhide_message(id) do
    case unhide_message_if_present(id) do
      {:ok, message} -> {:ok, message}
      {:error, :message_not_found} -> raise Ecto.NoResultsError
    end
  end

  @spec hide_message_if_present(integer() | String.t()) ::
          {:ok, Message.t()} | {:error, :message_not_found}
  def hide_message_if_present(id) do
    update_message_visibility(id, "hidden", "message.hidden")
  end

  @spec unhide_message_if_present(integer() | String.t()) ::
          {:ok, Message.t()} | {:error, :message_not_found}
  def unhide_message_if_present(id) do
    update_message_visibility(id, "visible", "message.updated")
  end

  @spec create_message({:human | :agent, actor()}, map()) ::
          {:ok, Message.t(), create_status()}
          | {:error,
             :body_required
             | :body_too_long
             | :invalid_reply_to_message
             | :invalid_client_message_id
             | Ecto.Changeset.t()}
  defp create_message({kind, actor}, attrs) do
    with {:ok, body} <- normalize_message_body(attrs),
         {:ok, client_message_id} <- normalize_client_message_id(attrs),
         {:ok, reply_to_message_id} <- validate_reply_to_message_id(attrs) do
      author_scope = author_scope(kind, actor)
      room_id = normalize_room_param(attrs, @global_room)

      if client_message_id do
        case Repo.get_by(Message,
               author_scope: author_scope,
               room_id: room_id,
               client_message_id: client_message_id
             ) do
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
      else
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

  defp insert_message(
         kind,
         actor,
         author_scope,
         room_id,
         body,
         client_message_id,
         reply_to_message_id
       ) do
    reply_to_transport_msg_id =
      case reply_to_message_id && Repo.get(Message, reply_to_message_id) do
        %Message{transport_msg_id: transport_msg_id} -> transport_msg_id
        _ -> nil
      end

    attrs =
      %{
        room_id: room_id,
        author_kind: kind,
        author_scope: author_scope,
        body: body,
        client_message_id: client_message_id,
        reply_to_message_id: reply_to_message_id,
        reply_to_transport_msg_id: reply_to_transport_msg_id,
        moderation_state: "visible",
        reactions: %{},
        transport_msg_id: transport_message_id(author_scope, room_id, client_message_id),
        transport_topic: Transport.topic_for_room(room_id),
        origin_node_id: Transport.origin_node_id(),
        transport_payload: %{}
      }
      |> put_author_ref(kind, actor)
      |> put_author_snapshot(kind, actor)

    case %Message{} |> Message.changeset(attrs) |> Repo.insert() do
      {:ok, message} ->
        message = preload_message(message)
        broadcast("message.created", message)
        {:ok, message, :created}

      {:error, %Ecto.Changeset{} = changeset} ->
        case find_message_by_client_message_id(author_scope, room_id, client_message_id) do
          %Message{} = existing ->
            {:ok, preload_message(existing), :existing}

          _ ->
            {:error, changeset}
        end
    end
  end

  defp public_messages_query do
    public_messages_query(true)
  end

  defp find_message_by_client_message_id(_author_scope, _room_id, nil), do: nil

  defp find_message_by_client_message_id(author_scope, room_id, client_message_id) do
    Repo.get_by(Message,
      author_scope: author_scope,
      room_id: room_id,
      client_message_id: client_message_id
    )
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

  defp fetch_public_message(message_id) do
    case public_messages_query() |> where([m], m.id == ^message_id) |> Repo.one() do
      %Message{} = message -> {:ok, message}
      nil -> {:error, :message_not_found}
    end
  end

  defp update_message_visibility(id, moderation_state, event) do
    with {:ok, normalized_id} <- parse_message_id(id, :message_not_found),
         %Message{} = message <- Repo.get(Message, normalized_id) do
      {:ok, updated} =
        message
        |> Ecto.Changeset.change(moderation_state: moderation_state)
        |> Repo.update()

      updated = preload_message(updated)
      broadcast(event, updated)
      {:ok, updated}
    else
      nil -> {:error, :message_not_found}
      {:error, :message_not_found} = error -> error
    end
  end

  defp preload_message(%Message{} = message) do
    Repo.preload(message, [:author_human, :author_agent])
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

  defp update_message_reactions(
         %Message{id: message_id},
         {actor_type, actor_ref},
         emoji,
         operation
       ) do
    Repo.transaction(fn ->
      message =
        Message
        |> where([m], m.id == ^message_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()
        |> Repo.preload([:author_human, :author_agent])

      with :ok <- apply_reaction_operation(message_id, actor_type, actor_ref, emoji, operation),
           updated_reactions <- reaction_counts_for_message(message_id),
           {:ok, updated} <-
             message
             |> Ecto.Changeset.change(reactions: updated_reactions)
             |> Repo.update() do
        Repo.preload(updated, [:author_human, :author_agent])
      else
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, %Message{} = updated} ->
        broadcast("reaction.updated", updated)
        {:ok, updated}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  @spec ingest_transport_event(binary(), map()) :: :ok | {:error, term()}
  def ingest_transport_event(topic, payload) when is_binary(topic) and is_map(payload) do
    with :ok <- validate_transport_payload(topic, payload),
         {:ok, message} <- upsert_transport_message(topic, payload) do
      fanout_local(payload["kind"], message)
    end
  end

  defp broadcast(event, %Message{} = message) do
    :ok = fanout_local(event, message)

    case Transport.build_and_publish(event, message) do
      :ok ->
        :ok

      {:error, :disabled} ->
        :ok

      {:error, reason} ->
        Logger.warning("chatbox mesh publish failed: #{inspect(reason)}")
        :ok
    end
  end

  defp fanout_local(event, %Message{} = message) do
    envelope = %{
      event: event,
      message: PublicEncoding.encode_chatbox_message(message)
    }

    Endpoint.broadcast(@channel_topic, event, envelope)
    Phoenix.PubSub.broadcast(TechTree.PubSub, @relay_topic, {:chatbox_event, envelope})
    :telemetry.execute([:tech_tree, :chatbox, :relay, :broadcast], %{count: 1}, %{event: event})
    :ok
  end

  defp put_author_ref(attrs, :human, %HumanUser{} = human),
    do: Map.put(attrs, :author_human_id, human.id)

  defp put_author_ref(attrs, :agent, %AgentIdentity{} = agent),
    do: Map.put(attrs, :author_agent_id, agent.id)

  defp put_author_snapshot(attrs, :human, %HumanUser{} = human) do
    attrs
    |> Map.put(:author_transport_id, "human:#{human.id}")
    |> Map.put(:author_display_name_snapshot, human.display_name)
    |> Map.put(:author_wallet_address_snapshot, human.wallet_address)
  end

  defp put_author_snapshot(attrs, :agent, %AgentIdentity{} = agent) do
    attrs
    |> Map.put(:author_transport_id, "agent:#{agent.id}")
    |> Map.put(:author_label_snapshot, agent.label)
    |> Map.put(:author_wallet_address_snapshot, agent.wallet_address)
  end

  defp ready_reaction_identity(%HumanUser{} = human) do
    case XmtpIdentity.ready_inbox_id(human) do
      {:ok, inbox_id} -> {:ok, inbox_id}
      {:error, :wallet_address_required} -> {:error, :xmtp_identity_required}
      {:error, :xmtp_identity_required} -> {:error, :xmtp_identity_required}
    end
  end

  defp author_scope(:human, %HumanUser{id: id}), do: "human:#{id}"
  defp author_scope(:agent, %AgentIdentity{id: id}), do: "agent:#{id}"

  defp parse_limit(params) do
    params
    |> Map.get("limit", Map.get(params, :limit, @default_limit))
    |> case do
      value when is_integer(value) and value > 0 ->
        min(value, @max_limit)

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed, ""} when parsed > 0 -> min(parsed, @max_limit)
          _ -> @default_limit
        end

      _ ->
        @default_limit
    end
  end

  defp parse_before_id(params) do
    params
    |> Map.get("before", Map.get(params, :before))
    |> case do
      nil ->
        nil

      value when is_integer(value) and value > 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed, ""} when parsed > 0 -> parsed
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_message_id(value, error_code) do
    case value do
      id when is_integer(id) and id > 0 ->
        {:ok, id}

      id when is_binary(id) ->
        case Integer.parse(String.trim(id)) do
          {parsed, ""} when parsed > 0 -> {:ok, parsed}
          _ -> {:error, error_code}
        end

      _ ->
        {:error, error_code}
    end
  end

  defp normalize_message_body(attrs) when is_map(attrs) do
    body =
      Map.get(attrs, "body")
      |> case do
        nil -> Map.get(attrs, :body)
        value -> value
      end

    cond do
      not is_binary(body) ->
        {:error, :body_required}

      true ->
        trimmed = String.trim(body)

        cond do
          trimmed == "" -> {:error, :body_required}
          String.length(trimmed) > @max_message_length -> {:error, :body_too_long}
          true -> {:ok, trimmed}
        end
    end
  end

  defp normalize_client_message_id(attrs) when is_map(attrs) do
    attrs
    |> Map.get("client_message_id", Map.get(attrs, :client_message_id))
    |> case do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:ok, nil}
          normalized when byte_size(normalized) > 128 -> {:error, :invalid_client_message_id}
          normalized -> {:ok, normalized}
        end

      _ ->
        {:error, :invalid_client_message_id}
    end
  end

  defp validate_reply_to_message_id(attrs) when is_map(attrs) do
    room_id = normalize_room_param(attrs, @global_room)

    attrs
    |> Map.get("reply_to_message_id", Map.get(attrs, :reply_to_message_id))
    |> case do
      nil ->
        {:ok, nil}

      value ->
        with {:ok, reply_to_message_id} <- parse_message_id(value, :invalid_reply_to_message),
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

  defp normalize_reaction_emoji(attrs) do
    attrs
    |> Map.get(
      "emoji",
      Map.get(attrs, :emoji, Map.get(attrs, "reaction", Map.get(attrs, :reaction)))
    )
    |> case do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, :invalid_reaction_emoji}
          normalized when byte_size(normalized) > 32 -> {:error, :invalid_reaction_emoji}
          normalized -> {:ok, normalized}
        end

      _ ->
        {:error, :invalid_reaction_emoji}
    end
  end

  defp normalize_reaction_operation(attrs) do
    attrs
    |> Map.get(
      "op",
      Map.get(attrs, :op, Map.get(attrs, "action", Map.get(attrs, :action, "add")))
    )
    |> case do
      value when is_binary(value) ->
        case String.trim(value) |> String.downcase() do
          "add" -> {:ok, :add}
          "remove" -> {:ok, :remove}
          _ -> {:error, :invalid_reaction_operation}
        end

      _ ->
        {:error, :invalid_reaction_operation}
    end
  end

  defp apply_reaction_operation(message_id, actor_type, actor_ref, emoji, :add) do
    %MessageReaction{}
    |> MessageReaction.changeset(%{
      message_id: message_id,
      actor_kind: actor_type,
      actor_ref: actor_ref,
      reaction: emoji
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:message_id, :actor_kind, :actor_ref, :reaction]
    )
    |> case do
      {:ok, _reaction} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp apply_reaction_operation(message_id, actor_type, actor_ref, emoji, :remove) do
    MessageReaction
    |> where(
      [reaction],
      reaction.message_id == ^message_id and reaction.actor_kind == ^actor_type and
        reaction.actor_ref == ^actor_ref and reaction.reaction == ^emoji
    )
    |> Repo.delete_all()

    :ok
  end

  defp reaction_counts_for_message(message_id) do
    MessageReaction
    |> where([reaction], reaction.message_id == ^message_id)
    |> group_by([reaction], reaction.reaction)
    |> select([reaction], {reaction.reaction, count(reaction.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp maybe_preload_public_message_authors(query, true) do
    preload(query, [_m, h, a], author_human: h, author_agent: a)
  end

  defp maybe_preload_public_message_authors(query, false), do: query

  defp actor_identity(%HumanUser{id: id}), do: {:human, id}
  defp actor_identity(%AgentIdentity{id: id}), do: {:agent, id}

  defp normalize_room_param(params, default) when is_map(params) do
    params
    |> Map.get("room_id", Map.get(params, :room_id, default))
    |> case do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> default
          trimmed -> trimmed
        end

      _ ->
        default
    end
  end

  defp normalize_agent_room(attrs, %AgentIdentity{id: id}) do
    case Map.get(attrs, "room", Map.get(attrs, :room, "agent")) do
      value when value in ["agent", :agent] -> "agent:#{id}"
      _ -> "agent:#{id}"
    end
  end

  defp validate_transport_payload(topic, %{
         "transport_msg_id" => transport_msg_id,
         "topic" => payload_topic,
         "actor" => %{"type" => actor_type},
         "inserted_at" => inserted_at
       })
       when is_binary(transport_msg_id) and is_binary(payload_topic) and is_binary(actor_type) and
              is_binary(inserted_at) do
    cond do
      topic != payload_topic -> {:error, :topic_mismatch}
      actor_type not in ["human", "agent"] -> {:error, :invalid_actor_type}
      true -> :ok
    end
  end

  defp validate_transport_payload(_topic, _payload), do: {:error, :invalid_payload}

  defp upsert_transport_message(topic, payload) do
    transport_msg_id = payload["transport_msg_id"]
    actor = payload["actor"] || %{}
    room_id = payload["room_id"] || @global_room
    reply_to_transport_msg_id = payload["reply_to_transport_msg_id"]

    reply_to_message_id =
      case reply_to_transport_msg_id do
        value when is_binary(value) ->
          case Repo.get_by(Message, transport_msg_id: value) do
            %Message{id: id} -> id
            _ -> nil
          end

        _ ->
          nil
      end

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
      reply_to_message_id: reply_to_message_id,
      reactions: payload["reactions"] || %{},
      moderation_state: payload["moderation_state"] || "visible",
      transport_msg_id: transport_msg_id,
      transport_topic: topic,
      origin_peer_id: payload["origin_peer_id"],
      origin_node_id: payload["origin_node_id"],
      transport_payload: payload,
      inserted_at: parse_transport_datetime(payload["inserted_at"]),
      updated_at: parse_transport_datetime(payload["updated_at"]) || DateTime.utc_now()
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

  defp parse_transport_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_transport_datetime(_value), do: nil
end
