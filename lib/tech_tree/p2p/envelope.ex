defmodule TechTree.P2P.Envelope do
  @moduledoc false

  alias Jason.OrderedObject
  alias Libp2p.Crypto.Secp256k1
  alias Libp2p.Identity
  alias Libp2p.PeerId
  alias TechTree.Chatbox.Message

  @version 1

  @spec build(binary(), binary(), Message.t(), Identity.t(), binary()) :: map()
  def build(event, topic, %Message{} = message, %Identity{} = identity, origin_node_id)
      when is_binary(event) and is_binary(topic) and is_binary(origin_node_id) do
    unsigned =
      %{
        "v" => @version,
        "kind" => event,
        "topic" => topic,
        "room_id" => message.room_id || "global",
        "transport_msg_id" => message.transport_msg_id,
        "origin_node_id" => origin_node_id,
        "origin_peer_id" => PeerId.to_base58(identity.peer_id),
        "origin_pubkey" => Base.encode64(identity.pubkey_compressed),
        "actor" => %{
          "type" => to_string(message.author_kind),
          "id" => message.author_transport_id || message.author_scope,
          "address" => message.author_wallet_address_snapshot,
          "display_name" => message.author_display_name_snapshot,
          "label" => message.author_label_snapshot
        },
        "body" => message.body,
        "client_message_id" => message.client_message_id,
        "reply_to_transport_msg_id" => message.reply_to_transport_msg_id,
        "reactions" => message.reactions || %{},
        "moderation_state" => message.moderation_state,
        "inserted_at" => encode_datetime(message.inserted_at),
        "updated_at" => encode_datetime(message.updated_at)
      }

    Map.put(unsigned, "sig", sign(unsigned, identity))
  end

  @spec encode!(map()) :: binary()
  def encode!(payload) when is_map(payload), do: Jason.encode!(payload)

  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  def decode(data) when is_binary(data), do: Jason.decode(data)

  @spec verify(map()) :: :ok | {:error, term()}
  def verify(
        %{"sig" => sig, "origin_pubkey" => origin_pubkey, "origin_peer_id" => origin_peer_id} =
          payload
      )
      when is_binary(sig) and is_binary(origin_pubkey) and is_binary(origin_peer_id) do
    unsigned = Map.delete(payload, "sig")
    compressed_pubkey = Base.decode64!(origin_pubkey)

    derived_peer_id =
      compressed_pubkey |> PeerId.from_secp256k1_pubkey_compressed() |> PeerId.to_base58()

    cond do
      derived_peer_id != origin_peer_id ->
        {:error, :peer_id_mismatch}

      Secp256k1.verify_bitcoin(
        Secp256k1.decompress_pubkey(compressed_pubkey),
        canonical_json(unsigned),
        Base.decode64!(sig)
      ) ->
        :ok

      true ->
        {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  def verify(_payload), do: {:error, :invalid_signature}

  @spec canonical_json(map()) :: binary()
  def canonical_json(payload) when is_map(payload) do
    payload
    |> canonical_value()
    |> Jason.encode!()
  end

  defp sign(payload, %Identity{} = identity) do
    payload
    |> canonical_json()
    |> then(&Secp256k1.sign_bitcoin(identity.privkey, &1))
    |> Base.encode64()
  end

  defp canonical_value(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {to_string(key), canonical_value(nested)} end)
    |> Enum.sort_by(fn {key, _nested} -> key end)
    |> OrderedObject.new()
  end

  defp canonical_value(value) when is_list(value), do: Enum.map(value, &canonical_value/1)
  defp canonical_value(value), do: value

  defp encode_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp encode_datetime(_value), do: nil
end
