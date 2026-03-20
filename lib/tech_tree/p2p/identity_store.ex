defmodule TechTree.P2P.IdentityStore do
  @moduledoc false

  alias Libp2p.Identity

  @spec load_or_create!(String.t()) :: Identity.t()
  def load_or_create!(path) when is_binary(path) do
    case File.read(path) do
      {:ok, raw} ->
        raw
        |> Jason.decode!()
        |> from_map()

      {:error, :enoent} ->
        identity = Identity.generate_secp256k1()
        path |> Path.dirname() |> File.mkdir_p!()
        File.write!(path, Jason.encode!(to_map(identity), pretty: true) <> "\n")
        identity

      {:error, reason} ->
        raise "unable to read libp2p identity from #{path}: #{inspect(reason)}"
    end
  end

  defp to_map(%Identity{} = identity) do
    %{
      "privkey" => Base.encode64(identity.privkey),
      "pubkey_uncompressed" => Base.encode64(identity.pubkey_uncompressed),
      "pubkey_compressed" => Base.encode64(identity.pubkey_compressed),
      "peer_id" => Base.encode64(identity.peer_id)
    }
  end

  defp from_map(%{
         "privkey" => privkey,
         "pubkey_uncompressed" => pubkey_uncompressed,
         "pubkey_compressed" => pubkey_compressed,
         "peer_id" => peer_id
       }) do
    %Identity{
      privkey: Base.decode64!(privkey),
      pubkey_uncompressed: Base.decode64!(pubkey_uncompressed),
      pubkey_compressed: Base.decode64!(pubkey_compressed),
      peer_id: Base.decode64!(peer_id)
    }
  end
end
