defmodule TechTree.Dragonfly do
  @moduledoc false

  @spec enabled?() :: boolean()
  def enabled?, do: RegentCache.Dragonfly.enabled?(:tech_tree)

  @spec command([term()]) :: {:ok, term()} | {:error, term()}
  def command(command), do: RegentCache.Dragonfly.command(:tech_tree, command)
end
