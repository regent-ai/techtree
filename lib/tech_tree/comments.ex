defmodule TechTree.Comments do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Repo
  alias TechTree.Comments.Comment
  alias TechTree.Nodes.Node
  alias TechTree.Workers.PinCommentWorker

  @spec list_public_for_node(integer() | String.t(), map()) :: [Comment.t()]
  def list_public_for_node(node_id, params) do
    limit = parse_limit(params, 100)
    normalized_node_id = normalize_id(node_id)

    Comment
    |> where([c], c.node_id == ^normalized_node_id and c.status == :ready)
    |> where([c], c.author_agent_id in subquery(active_agent_ids_query()))
    |> where([c], c.node_id in subquery(public_node_ids_query()))
    |> order_by([c], asc: c.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec create_agent_comment(TechTree.Agents.AgentIdentity.t(), integer() | String.t(), map()) ::
          {:ok, Comment.t()} | {:error, :comments_locked | Ecto.Changeset.t() | term()}
  def create_agent_comment(agent, node_id, attrs) do
    normalized_node_id = normalize_id(node_id)
    node = Repo.get!(Node, normalized_node_id)

    if node.comments_locked do
      {:error, :comments_locked}
    else
      Multi.new()
      |> Multi.insert(
        :comment,
        Comment.creation_changeset(%Comment{}, agent, normalized_node_id, attrs)
      )
      |> Multi.run(:oban, fn _repo, %{comment: comment} ->
        Oban.insert(PinCommentWorker.new(%{"comment_id" => comment.id}))
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{comment: comment}} -> {:ok, comment}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @spec mark_comment_ready!(integer() | String.t(), map()) :: :ok
  def mark_comment_ready!(comment_id, attrs) do
    comment = Repo.get!(Comment, normalize_id(comment_id))

    comment
    |> Comment.ready_changeset(Map.put(attrs, :status, :ready))
    |> Repo.update!()

    :ok
  end

  @spec update_search_document!(integer() | String.t()) :: :ok
  def update_search_document!(_comment_id), do: :ok

  @spec increment_node_comment_count!(integer() | String.t()) :: :ok
  def increment_node_comment_count!(node_id) do
    Node
    |> where([n], n.id == ^normalize_id(node_id))
    |> Repo.update_all(inc: [comment_count: 1])

    :ok
  end

  @spec normalize_id(integer() | String.t()) :: integer()
  defp normalize_id(value) when is_integer(value), do: value
  defp normalize_id(value) when is_binary(value), do: String.to_integer(value)

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
