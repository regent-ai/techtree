defmodule TechTree.Chatbox do
  @moduledoc false

  alias TechTree.Accounts.HumanUser
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Chatbox.Message
  alias TechTree.Chatbox.Messages
  alias TechTree.Chatbox.Payload
  alias TechTree.Chatbox.Reactions
  alias TechTree.Chatbox.Relay

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
  def subscribe, do: Relay.subscribe(@relay_topic)

  @spec list_public_messages(map()) :: %{messages: [Message.t()], next_cursor: integer() | nil}
  def list_public_messages(params \\ %{}) when is_map(params) do
    Messages.list_public_messages(params,
      default_room: @global_room,
      default_limit: @default_limit,
      max_limit: @max_limit
    )
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
  def create_human_message(%HumanUser{} = human, attrs) when is_map(attrs) do
    with :ok <- TechTree.Chatbox.Actor.ensure_can_post(human),
         {:ok, message, status} <-
           Messages.create_message({:human, human}, Map.put_new(attrs, :room_id, @global_room),
             default_room: @global_room,
             max_message_length: @max_message_length
           ) do
      maybe_broadcast_created(message, status)
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
  def create_agent_message(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    with :ok <- TechTree.Chatbox.Actor.ensure_can_post(agent),
         {:ok, message, status} <-
           Messages.create_message(
             {:agent, agent},
             Map.put_new(attrs, :room_id, Payload.normalize_agent_room(attrs, agent)),
             default_room: @global_room,
             max_message_length: @max_message_length
           ) do
      maybe_broadcast_created(message, status)
    end
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
  def react_to_message(actor, message_id, attrs) when is_map(attrs) do
    with {:ok, message} <- Reactions.react_to_message(actor, message_id, attrs) do
      :ok = Relay.broadcast("reaction.updated", message, @channel_topic, @relay_topic)
      {:ok, message}
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
    case Messages.update_visibility(id, "hidden") do
      {:ok, message} ->
        :ok = Relay.broadcast("message.hidden", message, @channel_topic, @relay_topic)
        {:ok, message}

      {:error, :message_not_found} = error ->
        error
    end
  end

  @spec unhide_message_if_present(integer() | String.t()) ::
          {:ok, Message.t()} | {:error, :message_not_found}
  def unhide_message_if_present(id) do
    case Messages.update_visibility(id, "visible") do
      {:ok, message} ->
        :ok = Relay.broadcast("message.updated", message, @channel_topic, @relay_topic)
        {:ok, message}

      {:error, :message_not_found} = error ->
        error
    end
  end

  @spec ingest_transport_event(binary(), map()) :: :ok | {:error, term()}
  def ingest_transport_event(topic, payload) when is_binary(topic) and is_map(payload) do
    with {:ok, event, message} <-
           Messages.ingest_transport_message(topic, payload, default_room: @global_room) do
      Relay.fanout_local(event, message, @channel_topic, @relay_topic)
    end
  end

  defp maybe_broadcast_created(message, :created) do
    :ok = Relay.broadcast("message.created", message, @channel_topic, @relay_topic)
    {:ok, message, :created}
  end

  defp maybe_broadcast_created(message, :existing), do: {:ok, message, :existing}
end
