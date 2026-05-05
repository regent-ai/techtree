defmodule TechTreeWeb.BenchmarkController do
  use TechTreeWeb, :controller

  alias TechTree.Benchmarks
  alias TechTreeWeb.ApiError

  def capsules(conn, params) do
    data =
      params
      |> Benchmarks.list_public_capsules()
      |> Enum.map(&Benchmarks.encode_capsule/1)

    json(conn, %{data: data})
  end

  def capsule(conn, %{"id" => capsule_id}) do
    case Benchmarks.get_public_capsule(capsule_id) do
      {:ok, capsule} ->
        json(conn, %{data: Benchmarks.encode_capsule(capsule)})

      {:error, :capsule_not_found} ->
        not_found(conn, "benchmark_capsule_not_found", "Benchmark capsule not found")
    end
  end

  def versions(conn, %{"id" => capsule_id}) do
    case Benchmarks.get_public_capsule(capsule_id) do
      {:ok, _capsule} ->
        data =
          capsule_id
          |> Benchmarks.list_public_capsule_versions()
          |> Enum.map(&Benchmarks.encode_capsule_version/1)

        json(conn, %{data: data})

      {:error, :capsule_not_found} ->
        not_found(conn, "benchmark_capsule_not_found", "Benchmark capsule not found")
    end
  end

  def scoreboard(conn, %{"id" => capsule_id} = params) do
    case Benchmarks.get_public_capsule(capsule_id) do
      {:ok, _capsule} ->
        scoreboard = Benchmarks.scoreboard(capsule_id, params)
        entries = Enum.map(scoreboard.entries, &Benchmarks.encode_reliability_summary/1)
        json(conn, %{data: %{capsule_id: capsule_id, entries: entries}})

      {:error, :capsule_not_found} ->
        not_found(conn, "benchmark_capsule_not_found", "Benchmark capsule not found")
    end
  end

  def reliability(conn, %{"id" => capsule_id}) do
    case Benchmarks.get_public_capsule(capsule_id) do
      {:ok, _capsule} ->
        data =
          capsule_id
          |> Benchmarks.reliability_summaries()
          |> Enum.map(&Benchmarks.encode_reliability_summary/1)

        json(conn, %{data: data})

      {:error, :capsule_not_found} ->
        not_found(conn, "benchmark_capsule_not_found", "Benchmark capsule not found")
    end
  end

  def attempt(conn, %{"id" => attempt_id}) do
    with {:ok, attempt} <- Benchmarks.get_public_attempt(attempt_id) do
      json(conn, %{data: Benchmarks.encode_attempt(attempt)})
    else
      {:error, :attempt_not_found} ->
        not_found(conn, "benchmark_attempt_not_found", "Benchmark attempt not found")
    end
  end

  def attempt_validations(conn, %{"id" => attempt_id}) do
    with {:ok, attempt} <- Benchmarks.get_public_attempt(attempt_id) do
      data =
        attempt.attempt_id
        |> Benchmarks.list_attempt_validations()
        |> Enum.map(&Benchmarks.encode_validation/1)

      json(conn, %{data: data})
    else
      {:error, :attempt_not_found} ->
        not_found(conn, "benchmark_attempt_not_found", "Benchmark attempt not found")
    end
  end

  def harness(conn, %{"id" => harness_id}) do
    case Benchmarks.get_harness(harness_id) do
      {:ok, harness} ->
        json(conn, %{data: Benchmarks.encode_harness(harness)})

      {:error, :harness_not_found} ->
        not_found(conn, "benchmark_harness_not_found", "Benchmark harness not found")
    end
  end

  defp not_found(conn, code, message) do
    ApiError.render_halted(conn, :not_found, %{"code" => code, "message" => message})
  end
end
