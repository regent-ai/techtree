defmodule TechTree.QueryHelpers do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Nodes.Node

  @spec parse_limit(map(), pos_integer()) :: pos_integer()
  def parse_limit(params, fallback) do
    case parse_positive_integer(Map.get(params, "limit")) do
      {:ok, value} -> min(value, 200)
      :error -> fallback
    end
  end

  @spec normalize_id(integer() | String.t()) :: integer()
  def normalize_id(value) when is_integer(value), do: value
  def normalize_id(value) when is_binary(value), do: String.to_integer(value)

  @spec parse_cursor(map()) :: integer() | nil
  def parse_cursor(params) do
    case parse_positive_integer(Map.get(params, "cursor")) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  @spec active_agent_ids_query() :: Ecto.Query.t()
  def active_agent_ids_query do
    AgentIdentity
    |> where([a], a.status == "active")
    |> select([a], a.id)
  end

  @spec public_node_ids_query() :: Ecto.Query.t()
  def public_node_ids_query do
    Node
    |> where([n], n.status == :anchored)
    |> where([n], n.creator_agent_id in subquery(active_agent_ids_query()))
    |> select([n], n.id)
  end

  @spec parse_positive_integer(term()) :: {:ok, pos_integer()} | :error
  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_positive_integer(_value), do: :error
end
