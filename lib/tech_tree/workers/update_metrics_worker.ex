defmodule TechTree.Workers.UpdateMetricsWorker do
  @moduledoc false
  use Oban.Worker, queue: :index, max_attempts: 10

  alias TechTree.Nodes
  alias TechTree.Repo
  alias TechTree.Nodes.Node

  @spec storage_policy() :: map()
  def storage_policy do
    %{
      canonical_store: :postgres,
      cache_dependency: :none,
      outage_behavior: :continue
    }
  end

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: %{"node_id" => node_id}}) do
    case Repo.get(Node, node_id) do
      nil ->
        :ok

      %Node{status: :anchored} = node ->
        score = Nodes.calculate_activity_score(node)

        if score_changed?(node.activity_score, score) do
          node
          |> Ecto.Changeset.change(activity_score: score)
          |> Repo.update!()
        end

        :ok

      %Node{} ->
        :ok
    end
  rescue
    error -> {:error, error}
  end

  @spec score_changed?(Decimal.t() | nil, Decimal.t()) :: boolean()
  defp score_changed?(nil, _next_score), do: true

  defp score_changed?(current_score, next_score),
    do: Decimal.compare(current_score, next_score) != :eq
end
