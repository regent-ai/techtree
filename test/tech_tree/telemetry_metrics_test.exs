defmodule TechTree.TelemetryMetricsTest do
  use ExUnit.Case, async: true

  test "exposes the expected runtime and request telemetry metrics" do
    metric_names =
      TechTreeWeb.Telemetry.metrics()
      |> Enum.map(&metric_name/1)

    expected_names = [
      "phoenix.endpoint.start.system_time",
      "phoenix.endpoint.stop.duration",
      "phoenix.router_dispatch.start.system_time",
      "phoenix.router_dispatch.exception.duration",
      "phoenix.router_dispatch.stop.duration",
      "phoenix.socket_connected.duration",
      "phoenix.socket_drain.count",
      "phoenix.channel_joined.duration",
      "phoenix.channel_handled_in.duration",
      "tech_tree.repo.query.total_time",
      "tech_tree.repo.query.decode_time",
      "tech_tree.repo.query.query_time",
      "tech_tree.repo.query.queue_time",
      "tech_tree.repo.query.idle_time",
      "vm.memory.total",
      "vm.total_run_queue_lengths.total",
      "vm.total_run_queue_lengths.cpu",
      "vm.total_run_queue_lengths.io"
    ]

    assert length(metric_names) == length(expected_names)
    assert Enum.sort(metric_names) == Enum.sort(expected_names)
  end

  defp metric_name(%{name: name}) when is_binary(name), do: name

  defp metric_name(%{name: name}) when is_list(name) do
    Enum.map_join(name, ".", &to_string/1)
  end
end
