defmodule TechTreeWeb.HealthController do
  use TechTreeWeb, :controller

  alias TechTree.RateLimit
  alias TechTree.Workers.RebuildHotScoresWorker
  alias TechTree.Workers.UpdateMetricsWorker

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, params) do
    json(conn, response_body(params))
  end

  defp response_body(%{"details" => details}) when details in ["1", "true", "full"] do
    rate_limit_status = RateLimit.status()

    %{
      ok: true,
      service: "tech_tree",
      cache: %{
        ready: rate_limit_status.cache_ready,
        degraded: rate_limit_status.degraded,
        rate_limit_backend: rate_limit_status.effective_backend,
        last_error: rate_limit_status.last_error,
        last_degraded_at_ms: rate_limit_status.last_degraded_at_ms,
        last_recovered_at_ms: rate_limit_status.last_recovered_at_ms
      },
      rate_limits: %{
        status: rate_limit_status,
        policy: RateLimit.policy()
      },
      rankings: %{
        status: RebuildHotScoresWorker.policy(),
        update_metrics: UpdateMetricsWorker.storage_policy()
      }
    }
  end

  defp response_body(_params), do: %{ok: true, service: "tech_tree"}
end
