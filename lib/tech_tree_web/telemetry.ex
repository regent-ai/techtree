defmodule TechTreeWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  @poller_period_ms 10_000
  @duration_unit {:native, :millisecond}

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      TechTree.Observability,
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: @poller_period_ms}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    phoenix_metrics() ++
      database_metrics() ++ techtree_metrics() ++ launch_kpi_metrics() ++ vm_metrics()
  end

  @spec phoenix_metrics() :: [Telemetry.Metrics.t()]
  defp phoenix_metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: @duration_unit
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: @duration_unit
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: @duration_unit
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: @duration_unit
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: @duration_unit
      ),
      summary("phoenix.socket_connected.duration",
        unit: @duration_unit
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: @duration_unit
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: @duration_unit
      )
    ]
  end

  @spec database_metrics() :: [Telemetry.Metrics.t()]
  defp database_metrics do
    [
      summary("tech_tree.repo.query.total_time",
        unit: @duration_unit,
        description: "The sum of the other measurements"
      ),
      summary("tech_tree.repo.query.decode_time",
        unit: @duration_unit,
        description: "The time spent decoding the data received from the database"
      ),
      summary("tech_tree.repo.query.query_time",
        unit: @duration_unit,
        description: "The time spent executing the query"
      ),
      summary("tech_tree.repo.query.queue_time",
        unit: @duration_unit,
        description: "The time spent waiting for a database connection"
      ),
      summary("tech_tree.repo.query.idle_time",
        unit: @duration_unit,
        description:
          "The time the connection spent waiting before being checked out for the query"
      )
    ]
  end

  @spec vm_metrics() :: [Telemetry.Metrics.t()]
  defp vm_metrics do
    [
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  @spec techtree_metrics() :: [Telemetry.Metrics.t()]
  defp techtree_metrics do
    [
      summary("tech_tree.nodes.publish.stop.duration", unit: @duration_unit),
      summary("tech_tree.nodes.anchor.stop.duration", unit: @duration_unit),
      sum("tech_tree.nodes.failed_anchor.count"),
      last_value("tech_tree.nodes.stale_pinned.count"),
      last_value("tech_tree.oban.queue_depth.count", tags: [:queue])
    ]
  end

  @spec launch_kpi_metrics() :: [Telemetry.Metrics.t()]
  defp launch_kpi_metrics do
    [
      sum("tech_tree.launch.nodes.publish.duration_total",
        event_name: [:tech_tree, :nodes, :publish, :stop],
        measurement: :duration,
        tags: [:outcome],
        unit: @duration_unit
      ),
      sum("tech_tree.launch.nodes.anchor.duration_total",
        event_name: [:tech_tree, :nodes, :anchor, :stop],
        measurement: :duration,
        tags: [:outcome],
        unit: @duration_unit
      ),
      sum("tech_tree.launch.nodes.transition.count",
        event_name: [:tech_tree, :nodes, :transition],
        measurement: :count,
        tags: [:from_status, :to_status, :outcome]
      ),
      sum("tech_tree.launch.watches.fanout.watcher_broadcasts",
        event_name: [:tech_tree, :watches, :fanout],
        measurement: :watcher_broadcasts,
        tags: [:outcome]
      ),
      sum("tech_tree.launch.watches.fanout.session_broadcasts",
        event_name: [:tech_tree, :watches, :fanout],
        measurement: :session_broadcasts,
        tags: [:outcome]
      ),
      summary("tech_tree.launch.workers.fanout_watcher_notifications.duration",
        event_name: [:tech_tree, :workers, :fanout_watcher_notifications, :stop],
        measurement: :duration,
        unit: @duration_unit
      ),
      sum("tech_tree.launch.agent.siwa.deny.count",
        event_name: [:tech_tree, :agent, :siwa, :deny],
        measurement: :count,
        tags: [:reason, :source]
      )
    ]
  end

  @spec periodic_measurements() :: [{module(), atom(), [term()]}]
  defp periodic_measurements do
    [
      {TechTree.Observability, :emit_periodic_metrics, []}
    ]
  end
end
