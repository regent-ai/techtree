defmodule TechTree.QueryHelpers do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Nodes.Node

  @spec parse_limit(map(), pos_integer()) :: pos_integer()
  def parse_limit(params, fallback) do
    case Map.get(params, "limit") do
      nil -> fallback
      value when is_integer(value) and value > 0 -> min(value, 200)
      value when is_integer(value) -> fallback
      value when is_binary(value) -> value |> String.to_integer() |> clamp_limit(fallback)
      _ -> fallback
    end
  rescue
    _ -> fallback
  end

  @spec normalize_id(integer() | String.t()) :: integer()
  def normalize_id(value) when is_integer(value), do: value
  def normalize_id(value) when is_binary(value), do: String.to_integer(value)

  @spec parse_cursor(map()) :: integer() | nil
  def parse_cursor(params) do
    case Map.get(params, "cursor") do
      value when is_integer(value) and value > 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {cursor, ""} when cursor > 0 -> cursor
          _ -> nil
        end

      _ ->
        nil
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

  @spec clamp_limit(integer(), pos_integer()) :: pos_integer()
  defp clamp_limit(value, fallback) when value <= 0, do: fallback
  defp clamp_limit(value, _fallback), do: min(value, 200)
end
