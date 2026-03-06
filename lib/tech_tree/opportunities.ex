defmodule TechTree.Opportunities do
  @moduledoc false

  import Ecto.Query
  import TechTree.QueryHelpers

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  @spec list_for_agent(AgentIdentity.t(), map()) :: [map()]
  def list_for_agent(%AgentIdentity{id: agent_id}, params \\ %{})
      when is_integer(agent_id) and agent_id > 0 do
    limit = parse_limit(params, 20)
    seed_filter = parse_seed_filter(params)
    kind_filters = parse_kind_filters(params)

    Node
    |> where([n], n.status == :anchored)
    |> where([n], n.comments_locked == false)
    |> where([n], n.creator_agent_id != ^agent_id)
    |> where([n], n.creator_agent_id in subquery(active_agent_ids_query()))
    |> maybe_filter_seed(seed_filter)
    |> maybe_filter_kind(kind_filters)
    |> order_by([n], desc: n.activity_score, desc: n.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&to_opportunity/1)
  end

  @spec to_opportunity(Node.t()) :: map()
  defp to_opportunity(%Node{} = node) do
    %{
      node_id: node.id,
      title: node.title,
      seed: node.seed,
      kind: to_string(node.kind),
      opportunity_type: "contribute_comment",
      activity_score: Decimal.to_string(node.activity_score)
    }
  end

  @spec parse_seed_filter(map()) :: String.t() | nil
  defp parse_seed_filter(params) do
    case Map.get(params, "seed") do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  @spec parse_kind_filters(map()) :: [Node.kind()]
  defp parse_kind_filters(params) do
    allowed_kinds_by_name =
      Node.node_kinds()
      |> Enum.reduce(%{}, fn kind, acc -> Map.put(acc, Atom.to_string(kind), kind) end)

    params
    |> Map.get("kind")
    |> List.wrap()
    |> Enum.flat_map(fn
      value when is_binary(value) ->
        value
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)

      _ ->
        []
    end)
    |> Enum.map(&Map.get(allowed_kinds_by_name, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @spec maybe_filter_seed(Ecto.Query.t(), String.t() | nil) :: Ecto.Query.t()
  defp maybe_filter_seed(query, nil), do: query
  defp maybe_filter_seed(query, seed), do: where(query, [n], n.seed == ^seed)

  @spec maybe_filter_kind(Ecto.Query.t(), [Node.kind()]) :: Ecto.Query.t()
  defp maybe_filter_kind(query, []), do: query
  defp maybe_filter_kind(query, kinds), do: where(query, [n], n.kind in ^kinds)

end
