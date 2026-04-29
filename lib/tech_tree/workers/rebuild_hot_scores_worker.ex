defmodule TechTree.Workers.RebuildHotScoresWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, max_attempts: 10

  alias TechTree.Nodes

  @spec policy() :: map()
  def policy do
    %{
      canonical_store: :postgres,
      cache_dependency: :none,
      outage_behavior: :fail_open_with_stale_cache_signal,
      rebuildable: true
    }
  end

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{}) do
    Nodes.refresh_hot_scores!()
    :ok
  rescue
    error -> {:error, error}
  end
end
