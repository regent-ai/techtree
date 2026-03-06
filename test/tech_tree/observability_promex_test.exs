defmodule TechTree.ObservabilityPromExTest do
  use ExUnit.Case, async: false

  test "wires PromEx plugins for Phoenix/Ecto/Oban and launch KPIs" do
    plugins = TechTree.Observability.plugins()

    assert Enum.any?(plugins, &match?({PromEx.Plugins.Phoenix, _opts}, &1))
    assert Enum.any?(plugins, &match?({PromEx.Plugins.Ecto, _opts}, &1))
    assert Enum.any?(plugins, &match?({PromEx.Plugins.Oban, _opts}, &1))
    assert Enum.member?(plugins, TechTree.Observability)
  end

  test "captures launch KPI metrics from existing telemetry events" do
    duration_native = System.convert_time_unit(125, :millisecond, :native)

    :telemetry.execute([:tech_tree, :nodes, :publish, :stop], %{duration: duration_native}, %{
      outcome: "ok"
    })

    :telemetry.execute([:tech_tree, :nodes, :anchor, :stop], %{duration: duration_native}, %{
      outcome: "transitioned"
    })

    :telemetry.execute(
      [:tech_tree, :nodes, :transition],
      %{count: 1},
      %{from_status: "pinned", to_status: "anchored", outcome: "ok"}
    )

    :telemetry.execute([:tech_tree, :nodes, :failed_anchor], %{count: 1}, %{node_id: 42})
    :telemetry.execute([:tech_tree, :nodes, :stale_pinned], %{count: 3}, %{threshold_minutes: 15})
    :telemetry.execute([:tech_tree, :oban, :queue_depth], %{count: 7}, %{queue: "realtime"})

    :telemetry.execute(
      [:tech_tree, :watches, :fanout],
      %{watcher_broadcasts: 2, session_broadcasts: 5},
      %{outcome: "ok", node_id: 9}
    )

    :telemetry.execute(
      [:tech_tree, :workers, :fanout_watcher_notifications, :stop],
      %{duration: duration_native},
      %{node_id: 9}
    )

    :telemetry.execute(
      [:tech_tree, :agent, :siwa, :deny],
      %{count: 1},
      %{reason: :missing_agent_headers, source: :request_headers}
    )

    metrics = fetch_metrics!()

    assert String.contains?(metrics, "tech_tree_prom_ex_launch_nodes_publish_total")
    assert String.contains?(metrics, "tech_tree_prom_ex_launch_nodes_anchor_total")
    assert String.contains?(metrics, "tech_tree_prom_ex_launch_nodes_failed_anchor_total")
    assert String.contains?(metrics, "tech_tree_prom_ex_launch_nodes_transition_total")
    assert String.contains?(metrics, "tech_tree_prom_ex_launch_nodes_stale_pinned_count")
    assert String.contains?(metrics, "tech_tree_prom_ex_launch_oban_queue_depth_count")

    assert String.contains?(
             metrics,
             "tech_tree_prom_ex_launch_watches_fanout_watcher_broadcasts_total"
           )

    assert String.contains?(
             metrics,
             "tech_tree_prom_ex_launch_watches_fanout_session_broadcasts_total"
           )

    assert String.contains?(
             metrics,
             "tech_tree_prom_ex_launch_workers_fanout_watcher_notifications_duration_milliseconds"
           )

    assert String.contains?(metrics, "tech_tree_prom_ex_launch_agent_siwa_deny_total")
  end

  test "keeps standalone metrics server disabled in test environment" do
    assert :disabled == TechTree.Observability.init_opts().metrics_server_config
  end

  defp fetch_metrics! do
    case PromEx.get_metrics(TechTree.Observability) do
      :prom_ex_down ->
        flunk("TechTree.Observability PromEx supervisor is not running")

      metrics when is_binary(metrics) ->
        metrics
    end
  end
end
