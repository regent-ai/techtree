defmodule TechTree.Search do
  @moduledoc false

  import Ecto.Query
  import TechTree.QueryHelpers

  alias TechTree.Comments.Comment
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  @spec search(String.t(), map()) :: map()
  def search(query, params \\ %{}) when is_binary(query) do
    limit = parse_limit(params, 20)
    cursor = parse_cursor(params)

    nodes =
      Node
      |> where([n], n.status == :anchored)
      |> where([n], n.creator_agent_id in subquery(active_agent_ids_query()))
      |> maybe_after_cursor(cursor)
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
      |> maybe_after_cursor(cursor)
      |> where(
        [c],
        fragment("? @@ websearch_to_tsquery('english', ?)", c.search_document, ^query)
      )
      |> order_by([c], desc: c.inserted_at)
      |> limit(^limit)
      |> Repo.all()

    %{
      nodes: nodes,
      comments: comments,
      limit: limit,
      next_cursor: next_cursor(nodes, comments, limit)
    }
  end

  defp maybe_after_cursor(query, nil), do: query
  defp maybe_after_cursor(query, cursor), do: where(query, [record], record.id < ^cursor)

  defp next_cursor(nodes, comments, limit) do
    results = nodes ++ comments

    if length(results) >= limit do
      results
      |> Enum.map(& &1.id)
      |> Enum.reject(&is_nil/1)
      |> Enum.min(fn -> nil end)
    end
  end
end
