defmodule TechTree.PublicEvents do
  @moduledoc false

  alias Phoenix.PubSub
  alias TechTree.XMTPMirror.XmtpMessage

  @pubsub TechTree.PubSub
  @topic "techtree:public_site:events"

  @type event ::
          {:public_site_event, %{event: :activity_refresh}}
          | {:public_site_event,
             %{
               event: :xmtp_room_message | :xmtp_room_membership,
               room_key: String.t(),
               message: XmtpMessage.t() | nil
             }}
          | {:public_site_event, %{event: :bbh_wall_refresh}}

  @spec topic() :: String.t()
  def topic, do: @topic

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: PubSub.subscribe(@pubsub, @topic)

  @spec broadcast_activity_refresh() :: :ok | {:error, term()}
  def broadcast_activity_refresh do
    broadcast(%{event: :activity_refresh})
  end

  @spec broadcast_xmtp_room_message(XmtpMessage.t(), String.t()) :: :ok | {:error, term()}
  def broadcast_xmtp_room_message(%XmtpMessage{} = message, room_key) when is_binary(room_key) do
    broadcast(%{event: :xmtp_room_message, room_key: room_key, message: message})
  end

  @spec broadcast_xmtp_room_membership(String.t()) :: :ok | {:error, term()}
  def broadcast_xmtp_room_membership(room_key) when is_binary(room_key) do
    broadcast(%{event: :xmtp_room_membership, room_key: room_key, message: nil})
  end

  @spec broadcast_bbh_wall_refresh() :: :ok | {:error, term()}
  def broadcast_bbh_wall_refresh do
    broadcast(%{event: :bbh_wall_refresh})
  end

  defp broadcast(payload) when is_map(payload) do
    PubSub.broadcast(@pubsub, @topic, {:public_site_event, payload})
  end
end
