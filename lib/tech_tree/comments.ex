defmodule TechTree.Comments do
  @moduledoc false

  import Ecto.Query
  import TechTree.QueryHelpers

  alias Ecto.Multi
  alias TechTree.Repo
  alias TechTree.Comments.Comment
  alias TechTree.Nodes.Node
  alias TechTree.Workers.{BroadcastCommentWorker, IndexCommentWorker}

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
          {:ok, Comment.t()}
          | {:error, :comments_locked | :node_not_found | Ecto.Changeset.t() | term()}
  def create_agent_comment(agent, node_id, attrs, opts \\ []) do
    normalized_node_id = normalize_id(node_id)
    skip_idempotency_lookup? = Keyword.get(opts, :skip_idempotency_lookup, false)
    node = Repo.get(Node, normalized_node_id)
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
              |> Multi.run(:index, fn _repo, %{comment: comment} ->
                Oban.insert(IndexCommentWorker.new(%{"comment_id" => comment.id}))
              end)
              |> Multi.run(:broadcast, fn _repo, %{comment: comment} ->
                Oban.insert(BroadcastCommentWorker.new(%{"comment_id" => comment.id}))
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

  @spec increment_node_comment_count!(integer() | String.t()) :: :ok
  def increment_node_comment_count!(node_id) do
    Node
    |> where([n], n.id == ^normalize_id(node_id))
    |> Repo.update_all(inc: [comment_count: 1])

    :ok
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
end