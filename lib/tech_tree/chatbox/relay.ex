defmodule TechTree.Chatbox.Relay do
  @moduledoc false

  require Logger

  alias TechTree.Chatbox.Message
  alias TechTree.P2P.Transport
  alias TechTreeWeb.{Endpoint, PublicEncoding}

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(relay_topic) when is_binary(relay_topic) do
    Phoenix.PubSub.subscribe(TechTree.PubSub, relay_topic)
  end

  @spec broadcast(String.t(), Message.t(), String.t(), String.t()) :: :ok
  def broadcast(event, %Message{} = message, channel_topic, relay_topic)
      when is_binary(event) and is_binary(channel_topic) and is_binary(relay_topic) do
    :ok = fanout_local(event, message, channel_topic, relay_topic)

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

  @spec fanout_local(String.t() | nil, Message.t(), String.t(), String.t()) :: :ok
  def fanout_local(event, %Message{} = message, channel_topic, relay_topic)
      when is_binary(channel_topic) and is_binary(relay_topic) do
    envelope = %{
      event: event,
      message: PublicEncoding.encode_chatbox_message(message)
    }

    Endpoint.broadcast(channel_topic, event, envelope)
    Phoenix.PubSub.broadcast(TechTree.PubSub, relay_topic, {:chatbox_event, envelope})
    :telemetry.execute([:tech_tree, :chatbox, :relay, :broadcast], %{count: 1}, %{event: event})
    :ok
  end
end
