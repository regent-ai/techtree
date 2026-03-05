defmodule TechTree.IPFS.Digests do
  @moduledoc false

  @spec sha256(binary()) :: binary()
  def sha256(data) when is_binary(data) do
    :crypto.hash(:sha256, data)
  end

  @spec sha256_hex(binary()) :: String.t()
  def sha256_hex(data) when is_binary(data) do
    data
    |> sha256()
    |> Base.encode16(case: :lower)
  end
end
