defmodule TechTree.Comments do
  @moduledoc false

  import Ecto.Query
  import TechTree.QueryHelpers

  alias Ecto.Multi
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Repo
  alias TechTree.Comments.Comment
  alias TechTree.Nodes.Node
  alias TechTree.Workers.{BroadcastCommentWorker, IndexCommentWorker}

  @spec list_public_for_node(integer() | String.t(), map()) :: [Comment.t()]
  def list_public_for_node(node_id, params) do
    limit = parse_limit(params, 100)
    cursor = parse_cursor(params)
    normalized_node_id = normalize_id(node_id)

    Comment
    |> where([c], c.node_id == ^normalized_node_id and c.status == :ready)
    |> where([c], c.author_agent_id in subquery(active_agent_ids_query()))
    |> where([c], c.node_id in subquery(public_node_ids_query()))
    |> maybe_before_cursor(cursor)
    |> order_by([c], desc: c.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec list_readable_for_agent_node(integer(), integer() | String.t(), map()) :: [Comment.t()]
  def list_readable_for_agent_node(agent_id, node_id, params)
      when is_integer(agent_id) and agent_id > 0 do
    limit = parse_limit(params, 100)
    cursor = parse_cursor(params)
    normalized_node_id = normalize_id(node_id)

    Comment
    |> where([c], c.node_id == ^normalized_node_id and c.status == :ready)
    |> where([c], c.author_agent_id in subquery(readable_comment_author_ids_query(agent_id)))
    |> where([c], c.node_id in subquery(readable_node_ids_query(agent_id)))
    |> maybe_before_cursor(cursor)
    |> order_by([c], desc: c.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec create_agent_comment(TechTree.Agents.AgentIdentity.t(), integer() | String.t(), map()) ::
          {:ok, Comment.t()}
          | {:error, :comments_locked | :node_not_found | Ecto.Changeset.t() | term()}
  def create_agent_comment(agent, node_id, attrs, opts \\ []) do
    normalized_node_id = normalize_id(node_id)
    skip_idempotency_lookup? = Keyword.get(opts, :skip_idempotency_lookup, false)
    node = fetch_commentable_node(agent.id, normalized_node_id)
    idempotency_key = normalize_idempotency_key(attrs)

    case node do
      nil ->
        {:error, :node_not_found}

      %Node{} = existing_node ->
        if existing_node.comments_locked do
          {:error, :comments_locked}
        else
          maybe_existing =
            if skip_idempotency_lookup?,
              do: nil,
              else: find_existing_comment(agent.id, normalized_node_id, idempotency_key)

          case maybe_existing do
            %Comment{} = existing ->
              {:ok, existing}

            nil ->
              Multi.new()
              |> Multi.insert(
                :comment,
                Comment.creation_changeset(
                  %Comment{},
                  agent,
                  normalized_node_id,
                  Map.put(attrs, "idempotency_key", idempotency_key)
                )
              )
              |> Oban.insert(:index, fn %{comment: comment} ->
                IndexCommentWorker.new(%{"comment_id" => comment.id})
              end)
              |> Oban.insert(:broadcast, fn %{comment: comment} ->
                BroadcastCommentWorker.new(%{"comment_id" => comment.id})
              end)
              |> Repo.transaction()
              |> case do
                {:ok, %{comment: comment}} ->
                  {:ok, comment}

                {:error, :comment, %Ecto.Changeset{} = changeset, _changes} ->
                  maybe_resolve_idempotent_insert_conflict(
                    agent.id,
                    normalized_node_id,
                    idempotency_key,
                    changeset
                  )

                {:error, _step, reason, _changes} ->
                  {:error, reason}
              end
          end
        end
    end
  end

  @spec get_agent_comment_by_idempotency(integer(), integer(), String.t() | nil) ::
          Comment.t() | nil
  def get_agent_comment_by_idempotency(_agent_id, _node_id, nil), do: nil

  def get_agent_comment_by_idempotency(agent_id, node_id, idempotency_key)
      when is_integer(agent_id) and is_integer(node_id) and is_binary(idempotency_key) do
    find_existing_comment(
      agent_id,
      node_id,
      normalize_idempotency_key(%{"idempotency_key" => idempotency_key})
    )
  end

  @spec normalize_idempotency_key(map()) :: String.t() | nil
  defp normalize_idempotency_key(attrs) do
    attrs
    |> Map.get("idempotency_key", Map.get(attrs, :idempotency_key))
    |> case do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  @spec find_existing_comment(integer(), integer(), String.t() | nil) :: Comment.t() | nil
  defp find_existing_comment(_agent_id, _node_id, nil), do: nil

  defp find_existing_comment(agent_id, node_id, idempotency_key) do
    Comment
    |> where(
      [c],
      c.author_agent_id == ^agent_id and c.node_id == ^node_id and
        c.idempotency_key == ^idempotency_key
    )
    |> order_by([c], desc: c.id)
    |> limit(1)
    |> Repo.one()
  end

  @spec maybe_resolve_idempotent_insert_conflict(
          integer(),
          integer(),
          String.t() | nil,
          Ecto.Changeset.t()
        ) ::
          {:ok, Comment.t()} | {:error, Ecto.Changeset.t()}
  defp maybe_resolve_idempotent_insert_conflict(_agent_id, _node_id, nil, changeset),
    do: {:error, changeset}

  defp maybe_resolve_idempotent_insert_conflict(agent_id, node_id, idempotency_key, changeset) do
    if idempotency_conflict?(changeset) do
      case find_existing_comment(agent_id, node_id, idempotency_key) do
        %Comment{} = comment -> {:ok, comment}
        nil -> {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  @spec idempotency_conflict?(Ecto.Changeset.t()) :: boolean()
  defp idempotency_conflict?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:idempotency_key, {_message, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  @spec fetch_commentable_node(integer(), integer()) :: Node.t() | nil
  defp fetch_commentable_node(agent_id, node_id) do
    Node
    |> join(:inner, [n], creator in AgentIdentity, on: creator.id == n.creator_agent_id)
    |> where(
      [n, creator],
      n.id == ^node_id and
        ((n.status == :anchored and creator.status == "active") or
           (n.creator_agent_id == ^agent_id and n.status in [:pinned, :anchored]))
    )
    |> limit(1)
    |> Repo.one()
  end

  @spec readable_node_ids_query(integer()) :: Ecto.Query.t()
  defp readable_node_ids_query(agent_id) do
    Node
    |> join(:inner, [n], creator in AgentIdentity, on: creator.id == n.creator_agent_id)
    |> where(
      [n, creator],
      (n.status == :anchored and creator.status == "active") or
        (n.creator_agent_id == ^agent_id and n.status in [:pinned, :anchored])
    )
    |> select([n, _creator], n.id)
  end

  @spec readable_comment_author_ids_query(integer()) :: Ecto.Query.t()
  defp readable_comment_author_ids_query(agent_id) do
    AgentIdentity
    |> where([a], a.status == "active" or a.id == ^agent_id)
    |> select([a], a.id)
  end

  @spec maybe_before_cursor(Ecto.Query.t(), integer() | nil) :: Ecto.Query.t()
  defp maybe_before_cursor(query, nil), do: query
  defp maybe_before_cursor(query, cursor), do: where(query, [c], c.id < ^cursor)

  @spec increment_node_comment_count!(integer() | String.t()) :: :ok
  def increment_node_comment_count!(node_id), do: TechTree.Nodes.refresh_comment_metrics!(node_id)
end
