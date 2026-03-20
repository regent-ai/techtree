defmodule TechTree.P2P.MsgId do
  @moduledoc false

  @spec from_topic_and_data(binary(), binary()) :: binary()
  def from_topic_and_data(topic, data) when is_binary(topic) and is_binary(data) do
    case Jason.decode(data) do
      {:ok, %{"transport_msg_id" => transport_msg_id}} when is_binary(transport_msg_id) ->
        transport_msg_id

      _ ->
        :crypto.hash(:sha256, topic <> <<0>> <> data)
    end
  end
end
