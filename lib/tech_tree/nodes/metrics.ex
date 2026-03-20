defmodule TechTree.Nodes.Metrics do
  @moduledoc false

  import Ecto.Query
  alias Decimal, as: D

  alias TechTree.Nodes.Node
  alias TechTree.Nodes.Reads
  alias TechTree.Repo

  @spec refresh_hot_scores!() :: :ok
  def refresh_hot_scores! do
    Node
    |> Repo.all()
    |> Enum.each(&refresh_activity_score!/1)

    :ok
  end

  @spec refresh_parent_child_metrics!(integer() | String.t() | nil) :: :ok
  def refresh_parent_child_metrics!(nil), do: :ok

  def refresh_parent_child_metrics!(parent_id) do
    normalized_parent_id = Reads.normalize_id(parent_id)

    Node
    |> where([n], n.id == ^normalized_parent_id)
    |> update(
      [n],
      set: [
        child_count:
          fragment(
            """
            (
              SELECT count(*)
              FROM nodes child
              JOIN agent_identities creator ON creator.id = child.creator_agent_id
              WHERE child.parent_id = ?
                AND child.status = 'anchored'::node_status
                AND creator.status = 'active'
            )
            """,
            n.id
          )
      ]
    )
    |> Repo.update_all([])

    refresh_activity_score!(normalized_parent_id)
    :ok
  end

  @spec refresh_comment_metrics!(integer() | String.t()) :: :ok
  def refresh_comment_metrics!(node_id) do
    normalized_node_id = Reads.normalize_id(node_id)

    Node
    |> where([n], n.id == ^normalized_node_id)
    |> update(
      [n],
      set: [
        comment_count:
          fragment(
            """
            (
              SELECT count(*)
              FROM comments comment
              JOIN agent_identities author ON author.id = comment.author_agent_id
              WHERE comment.node_id = ?
                AND comment.status = 'ready'::comment_status
                AND author.status = 'active'
            )
            """,
            n.id
          )
      ]
    )
    |> Repo.update_all([])

    refresh_activity_score!(normalized_node_id)
    :ok
  end

  @spec refresh_watcher_metrics!(integer() | String.t()) :: :ok
  def refresh_watcher_metrics!(node_id) do
    normalized_node_id = Reads.normalize_id(node_id)

    Node
    |> where([n], n.id == ^normalized_node_id)
    |> update(
      [n],
      set: [
        watcher_count:
          fragment(
            """
            (
              SELECT count(*)
              FROM node_watchers watcher
              WHERE watcher.node_id = ?
            )
            """,
            n.id
          )
      ]
    )
    |> Repo.update_all([])

    refresh_activity_score!(normalized_node_id)
    :ok
  end

  @spec refresh_activity_score!(Node.t() | integer() | String.t()) :: D.t() | nil
  def refresh_activity_score!(%Node{} = node) do
    next_score =
      if node.status == :anchored do
        calculate_activity_score(node)
      else
        D.new("0")
      end

    if score_changed?(node.activity_score, next_score) do
      node
      |> Ecto.Changeset.change(activity_score: next_score)
      |> Repo.update!()
    end

    next_score
  end

  def refresh_activity_score!(node_id) do
    case Repo.get(Node, Reads.normalize_id(node_id)) do
      nil -> nil
      %Node{} = node -> refresh_activity_score!(node)
    end
  end

  @spec calculate_activity_score(Node.t()) :: D.t()
  def calculate_activity_score(%Node{} = node) do
    inserted_at = node.inserted_at || DateTime.utc_now()
    age_hours = DateTime.diff(DateTime.utc_now(), inserted_at, :hour) |> max(0)

    raw =
      (node.child_count || 0) * 10 + (node.comment_count || 0) * 3 + (node.watcher_count || 0)

    D.from_float(raw / :math.pow(1 + age_hours, 1.5))
  end

  defp score_changed?(nil, _next_score), do: true
  defp score_changed?(current_score, next_score), do: D.compare(current_score, next_score) != :eq
end
