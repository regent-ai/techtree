defmodule TechTree.Observability do
  @moduledoc false

  import Ecto.Query
  import Telemetry.Metrics

  alias PromEx.MetricTypes.Event
  alias PromEx.Plugins

  alias TechTree.Nodes.Node
  alias TechTree.Repo

  use PromEx, otp_app: :tech_tree

  @stale_pinned_minutes 15
  @observed_queues ~w(chain index realtime xmtp maintenance)
  @active_job_states ~w(available scheduled retryable executing)
  @duration_unit {:native, :millisecond}

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, endpoint: TechTreeWeb.Endpoint, router: TechTreeWeb.Router},
      {Plugins.Ecto, repos: [TechTree.Repo]},
      {Plugins.Oban, oban_supervisors: [Oban]},
      __MODULE__
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end

  @spec event_metrics(keyword()) :: [Event.t()]
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    metric_prefix = Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :launch))

    [
      Event.build(
        :techtree_launch_kpi_event_metrics,
        launch_kpi_metrics(metric_prefix)
      )
    ]
  end

  @spec polling_metrics(keyword()) :: []
  def polling_metrics(_opts), do: []

  @spec manual_metrics(keyword()) :: []
  def manual_metrics(_opts), do: []

  @spec emit_periodic_metrics() :: :ok
  def emit_periodic_metrics do
    if repo_started?() do
      emit_stale_pinned_count()
      emit_queue_depths()
    end

    :ok
  end

  defp repo_started? do
    pid = Process.whereis(TechTree.Repo)
    is_pid(pid) and Process.alive?(pid)
  end

  @spec launch_kpi_metrics([atom()]) :: [Telemetry.Metrics.t()]
  defp launch_kpi_metrics(metric_prefix) do
    [
      distribution(
        metric_prefix ++ [:nodes, :publish, :duration, :milliseconds],
        event_name: [:tech_tree, :nodes, :publish, :stop],
        measurement: :duration,
        tags: [:outcome],
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1_000, 5_000, 10_000]],
        unit: @duration_unit
      ),
      counter(
        metric_prefix ++ [:nodes, :publish, :total],
        event_name: [:tech_tree, :nodes, :publish, :stop],
        tags: [:outcome]
      ),
      distribution(
        metric_prefix ++ [:nodes, :anchor, :duration, :milliseconds],
        event_name: [:tech_tree, :nodes, :anchor, :stop],
        measurement: :duration,
        tags: [:outcome],
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1_000, 5_000, 10_000]],
        unit: @duration_unit
      ),
      counter(
        metric_prefix ++ [:nodes, :anchor, :total],
        event_name: [:tech_tree, :nodes, :anchor, :stop],
        tags: [:outcome]
      ),
      counter(
        metric_prefix ++ [:nodes, :failed_anchor, :total],
        event_name: [:tech_tree, :nodes, :failed_anchor]
      ),
      counter(
        metric_prefix ++ [:nodes, :transition, :total],
        event_name: [:tech_tree, :nodes, :transition],
        tags: [:from_status, :to_status, :outcome]
      ),
      last_value(
        metric_prefix ++ [:nodes, :stale_pinned, :count],
        event_name: [:tech_tree, :nodes, :stale_pinned],
        measurement: :count
      ),
      last_value(
        metric_prefix ++ [:oban, :queue_depth, :count],
        event_name: [:tech_tree, :oban, :queue_depth],
        measurement: :count,
        tags: [:queue]
      ),
      sum(
        metric_prefix ++ [:watches, :fanout, :watcher_broadcasts, :total],
        event_name: [:tech_tree, :watches, :fanout],
        measurement: :watcher_broadcasts,
        tags: [:outcome]
      ),
      sum(
        metric_prefix ++ [:watches, :fanout, :session_broadcasts, :total],
        event_name: [:tech_tree, :watches, :fanout],
        measurement: :session_broadcasts,
        tags: [:outcome]
      ),
      distribution(
        metric_prefix ++ [:workers, :fanout_watcher_notifications, :duration, :milliseconds],
        event_name: [:tech_tree, :workers, :fanout_watcher_notifications, :stop],
        measurement: :duration,
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1_000]],
        unit: @duration_unit
      ),
      counter(
        metric_prefix ++ [:agent, :siwa, :deny, :total],
        event_name: [:tech_tree, :agent, :siwa, :deny],
        tags: [:reason, :source]
      )
    ]
  end

  @spec emit_stale_pinned_count() :: :ok
  defp emit_stale_pinned_count do
    stale_before = DateTime.add(DateTime.utc_now(), -@stale_pinned_minutes * 60, :second)

    count =
      Node
      |> where([n], n.status == :pinned and n.inserted_at < ^stale_before)
      |> Repo.aggregate(:count, :id)

    :telemetry.execute([:tech_tree, :nodes, :stale_pinned], %{count: count}, %{
      threshold_minutes: @stale_pinned_minutes
    })
  end

  @spec emit_queue_depths() :: :ok
  defp emit_queue_depths do
    Enum.each(@observed_queues, fn queue ->
      count =
        "oban_jobs"
        |> where([j], j.queue == ^queue and j.state in ^@active_job_states)
        |> Repo.aggregate(:count, :id)

      :telemetry.execute([:tech_tree, :oban, :queue_depth], %{count: count}, %{queue: queue})
    end)

    :ok
  end
end
