defmodule TechTree.Workers.UpdateMetricsWorker do
  @moduledoc false
  use Oban.Worker, queue: :index, max_attempts: 10

  require Logger

  alias TechTree.Repo
  alias TechTree.Nodes.Node

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: %{"node_id" => node_id}}) do
    case Repo.get(Node, node_id) do
      nil ->
        :ok

      %Node{status: :anchored} = node ->
        score = compute_activity_score(node)

        if score_changed?(node.activity_score, score) do
          node
          |> Ecto.Changeset.change(activity_score: score)
          |> Repo.update!()

          maybe_write_hot_set!("hot:nodes:global", node.id, score)

          if is_binary(node.seed) and byte_size(node.seed) > 0 do
            maybe_write_hot_set!("hot:nodes:seed:#{node.seed}", node.id, score)
          end
        end

        :ok

      %Node{} ->
        :ok
    end
  rescue
    error -> {:error, error}
  end

  @spec compute_activity_score(Node.t()) :: Decimal.t()
  defp compute_activity_score(node) do
    inserted_at = node.inserted_at || DateTime.utc_now()
    age_hours = DateTime.diff(DateTime.utc_now(), inserted_at, :hour) |> max(0)

    raw =
      (node.child_count || 0) * 10 + (node.comment_count || 0) * 3 + (node.watcher_count || 0)

    Decimal.from_float(raw / :math.pow(1 + age_hours, 1.5))
  end

  @spec score_changed?(Decimal.t() | nil, Decimal.t()) :: boolean()
  defp score_changed?(nil, _next_score), do: true

  defp score_changed?(current_score, next_score),
    do: Decimal.compare(current_score, next_score) != :eq

  @spec maybe_write_hot_set!(String.t(), integer(), Decimal.t()) :: :ok
  defp maybe_write_hot_set!(key, node_id, score) do
    case Redix.command(:dragonfly, ["ZADD", key, Decimal.to_string(score), to_string(node_id)]) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "dragonfly hot-set write failed key=#{key} node_id=#{node_id}: #{inspect(reason)}"
        )

        :ok
    end
  end
end
