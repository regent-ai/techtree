defmodule TechTree.Search do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Comments.Comment
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  @spec search(String.t(), map()) :: map()
  def search(query, params \\ %{}) when is_binary(query) do
    limit = parse_limit(params, 20)

    nodes =
      Node
      |> where([n], n.status == :ready)
      |> where([n], n.creator_agent_id in subquery(active_agent_ids_query()))
      |> where(
        [n],
        fragment("? @@ websearch_to_tsquery('english', ?)", n.search_document, ^query)
      )
      |> order_by([n], desc: n.inserted_at)
      |> limit(^limit)
      |> Repo.all()

    comments =
      Comment
      |> where([c], c.status == :ready)
      |> where([c], c.author_agent_id in subquery(active_agent_ids_query()))
      |> where([c], c.node_id in subquery(public_node_ids_query()))
      |> where(
        [c],
        fragment("? @@ websearch_to_tsquery('english', ?)", c.search_document, ^query)
      )
      |> order_by([c], desc: c.inserted_at)
      |> limit(^limit)
      |> Repo.all()

    %{nodes: nodes, comments: comments}
  end

  @spec parse_limit(map(), pos_integer()) :: pos_integer()
  defp parse_limit(params, fallback) do
    case Map.get(params, "limit") do
      nil -> fallback
      value when is_integer(value) and value > 0 -> min(value, 200)
      value when is_binary(value) -> value |> String.to_integer() |> min(200)
      _ -> fallback
    end
  rescue
    _ -> fallback
  end

  @spec active_agent_ids_query() :: Ecto.Query.t()
  defp active_agent_ids_query do
    AgentIdentity
    |> where([a], a.status == "active")
    |> select([a], a.id)
  end

  @spec public_node_ids_query() :: Ecto.Query.t()
  defp public_node_ids_query do
    Node
    |> where([n], n.status == :ready)
    |> where([n], n.creator_agent_id in subquery(active_agent_ids_query()))
    |> select([n], n.id)
  end
end
