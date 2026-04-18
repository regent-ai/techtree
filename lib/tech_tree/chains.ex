defmodule TechTree.Chains do
  @moduledoc false

  @supported %{
    8453 => "Base Mainnet",
    84_532 => "Base Sepolia"
  }

  @spec supported_chain_ids() :: [integer()]
  def supported_chain_ids, do: Map.keys(@supported)

  @spec supported_chain_id?(term()) :: boolean()
  def supported_chain_id?(chain_id) when is_integer(chain_id),
    do: Map.has_key?(@supported, chain_id)

  def supported_chain_id?(_chain_id), do: false

  @spec label(integer()) :: String.t() | nil
  def label(chain_id) when is_integer(chain_id), do: Map.get(@supported, chain_id)
  def label(_chain_id), do: nil
end
