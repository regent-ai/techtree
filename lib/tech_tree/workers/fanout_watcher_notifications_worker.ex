defmodule TechTree.Workers.FanoutWatcherNotificationsWorker do
  @moduledoc false
  use Oban.Worker, queue: :realtime, max_attempts: 10

  require Logger

  alias TechTree.Watches

  @worker_telemetry_event [:tech_tree, :workers, :fanout_watcher_notifications, :stop]

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"node_id" => node_id}}) do
    started_at = System.monotonic_time()

    :ok = Watches.fanout_node_activity(node_id)

    duration = System.monotonic_time() - started_at
    normalized_node_id = normalize_node_id(node_id)

    :telemetry.execute(@worker_telemetry_event, %{duration: duration}, %{
      node_id: normalized_node_id
    })

    Logger.debug(
      "fanout watcher worker completed node_id=#{normalized_node_id} duration=#{duration}"
    )

    :ok
  end

  @spec normalize_node_id(integer() | String.t()) :: integer() | String.t()
  defp normalize_node_id(value) when is_integer(value), do: value

  defp normalize_node_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> value
    end
  end
end
