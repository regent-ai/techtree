defmodule TechTree.P2P.Bootstrapper do
  @moduledoc false

  alias Libp2p.Multiaddr

  @type bootstrap_peer :: %{
          raw: binary(),
          peer_id: binary() | nil,
          ip: :inet.ip_address(),
          port: :inet.port_number()
        }

  @spec parse_peer(binary()) :: {:ok, bootstrap_peer()} | {:error, term()}
  def parse_peer(raw) when is_binary(raw) do
    multiaddr = Multiaddr.from_string(raw)

    with {:ok, {ip, port}} <- Multiaddr.to_tcp_socketaddr(multiaddr) do
      peer_id =
        Enum.find_value(multiaddr.protos, fn
          {:p2p, peer_id} -> peer_id
          _ -> nil
        end)

      {:ok, %{raw: raw, peer_id: peer_id, ip: ip, port: port}}
    end
  rescue
    error -> {:error, error}
  end
end
