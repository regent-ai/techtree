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

      %Node{status: :ready} = node ->
        score = compute_activity_score(node)

        node
        |> Ecto.Changeset.change(activity_score: score)
        |> Repo.update!()

        maybe_write_hot_set!("hot:nodes:global", node.id, score)

        if is_binary(node.seed) and byte_size(node.seed) > 0 do
          maybe_write_hot_set!("hot:nodes:seed:#{node.seed}", node.id, score)
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
    age_hours = DateTime.diff(DateTime.utc_now(), inserted_at, :second) / 3600.0

    raw = (node.child_count || 0) * 10 + (node.comment_count || 0) * 3 + (node.watcher_count || 0)
    Decimal.from_float(raw / :math.pow(1 + age_hours, 1.5))
  end

  @spec maybe_write_hot_set!(String.t(), integer(), Decimal.t()) :: :ok
  defp maybe_write_hot_set!(key, node_id, score) do
    case Redix.command(:dragonfly, ["ZADD", key, Decimal.to_string(score), to_string(node_id)]) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("dragonfly hot-set write failed key=#{key} node_id=#{node_id}: #{inspect(reason)}")
        :ok
    end
  end
end
