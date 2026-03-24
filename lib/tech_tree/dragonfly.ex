defmodule TechTree.Dragonfly do
  @moduledoc false

  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:tech_tree, :dragonfly_enabled, true) == true
  end

  @spec command([term()]) :: {:ok, term()} | {:error, term()}
  def command(command) when is_list(command) do
    if enabled?() do
      case redix_name() do
        nil ->
          {:error, :dragonfly_unavailable}

        name ->
          try do
            Redix.command(name, command)
          rescue
            error -> {:error, error}
          catch
            :exit, reason -> {:error, reason}
          end
      end
    else
      {:error, :dragonfly_disabled}
    end
  end

  def command(_command), do: {:error, :invalid_command}

  @spec redix_name() :: atom() | pid() | nil
  defp redix_name do
    Application.get_env(:tech_tree, :dragonfly_name, :dragonfly)
  end
end
