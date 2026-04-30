defmodule TechTree.Workers.RecomputeBenchmarkReliabilityWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :index,
    max_attempts: 10,
    unique: [period: 300, keys: [:capsule_id, :version_id, :harness_id, :repeat_group_id]]

  alias TechTree.Benchmarks

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{
        args: %{
          "capsule_id" => capsule_id,
          "version_id" => version_id,
          "harness_id" => harness_id,
          "repeat_group_id" => repeat_group_id
        }
      }) do
    case Benchmarks.recompute_reliability_group(
           capsule_id,
           version_id,
           harness_id,
           repeat_group_id
         ) do
      {:ok, _summary_or_nil} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
