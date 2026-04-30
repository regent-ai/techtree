defmodule TechTreeWeb.AgentBenchmarkController do
  use TechTreeWeb, :controller

  alias TechTree.Benchmarks
  alias TechTreeWeb.{AgentApiResult, ControllerHelpers}

  def create_capsule(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Benchmarks.create_capsule(agent, params) do
      {:ok, capsule} ->
        conn
        |> put_status(:created)
        |> json(%{data: Benchmarks.encode_capsule(capsule)})

      {:error, reason} ->
        render_error(conn, "benchmark_capsule_invalid", reason)
    end
  end

  def create_version(conn, %{"id" => capsule_id} = params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Benchmarks.create_capsule_version(agent, capsule_id, Map.delete(params, "id")) do
      {:ok, version} ->
        conn
        |> put_status(:created)
        |> json(%{data: Benchmarks.encode_capsule_version(version)})

      {:error, reason} ->
        render_error(conn, "benchmark_version_invalid", reason)
    end
  end

  def mark_review_ready(conn, %{"id" => capsule_id} = params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Benchmarks.mark_capsule_review_ready(agent, capsule_id, Map.delete(params, "id")) do
      {:ok, capsule} ->
        json(conn, %{data: Benchmarks.encode_capsule(capsule)})

      {:error, reason} ->
        render_error(conn, "benchmark_review_ready_failed", reason)
    end
  end

  def publish_capsule(conn, %{"id" => capsule_id} = params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Benchmarks.publish_capsule(agent, capsule_id, Map.delete(params, "id")) do
      {:ok, result} ->
        conn
        |> put_status(:created)
        |> json(%{
          data: %{
            capsule: Benchmarks.encode_capsule(result.capsule),
            version: Benchmarks.encode_capsule_version(result.version),
            publication_node: result.publication_node
          }
        })

      {:error, reason} ->
        render_error(conn, "benchmark_publish_failed", reason)
    end
  end

  def create_harness(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Benchmarks.create_harness(agent, params) do
      {:ok, harness} ->
        conn
        |> put_status(:created)
        |> json(%{data: Benchmarks.encode_harness(harness)})

      {:error, reason} ->
        render_error(conn, "benchmark_harness_invalid", reason)
    end
  end

  def create_attempt(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Benchmarks.create_attempt(agent, params) do
      {:ok, attempt} ->
        conn
        |> put_status(:created)
        |> json(%{data: Benchmarks.encode_attempt(attempt)})

      {:error, reason} ->
        render_error(conn, "benchmark_attempt_invalid", reason)
    end
  end

  def create_repeat_group(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Benchmarks.create_repeat_group(agent, params) do
      {:ok, result} ->
        conn
        |> put_status(:created)
        |> json(%{
          data: %{
            repeat_group_id: result.repeat_group_id,
            attempts: Enum.map(result.attempts, &Benchmarks.encode_attempt/1)
          }
        })

      {:error, reason} ->
        render_error(conn, "benchmark_repeat_group_invalid", reason)
    end
  end

  def create_validation(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Benchmarks.create_validation(agent, params) do
      {:ok, validation} ->
        conn
        |> put_status(:created)
        |> json(%{data: Benchmarks.encode_validation(validation)})

      {:error, reason} ->
        render_error(conn, "benchmark_validation_invalid", reason)
    end
  end

  def create_import(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Benchmarks.create_import(agent, params) do
      {:ok, result} ->
        conn
        |> put_status(:created)
        |> json(%{data: result})

      {:error, reason} ->
        render_error(conn, "benchmark_import_failed", reason)
    end
  end

  def recompute_reliability(conn, %{"id" => capsule_id}) do
    case Benchmarks.recompute_reliability(capsule_id) do
      {:ok, summaries} ->
        json(conn, %{data: Enum.map(summaries, &Benchmarks.encode_reliability_summary/1)})

      {:error, reason} ->
        render_error(conn, "benchmark_reliability_recompute_failed", reason)
    end
  end

  defp render_error(conn, code, %Ecto.Changeset{} = changeset) do
    AgentApiResult.render_changeset(conn, :unprocessable_entity, code, changeset)
  end

  defp render_error(conn, code, reason)
       when reason in [
              :capsule_not_found,
              :capsule_version_not_found,
              :attempt_not_found,
              :harness_not_found
            ] do
    AgentApiResult.render_message(conn, :not_found, code, public_reason(reason))
  end

  defp render_error(conn, code, reason) do
    AgentApiResult.render_message(conn, :unprocessable_entity, code, public_reason(reason))
  end

  defp public_reason(:capsule_not_found), do: "Benchmark capsule not found"
  defp public_reason(:attempt_not_found), do: "Benchmark attempt not found"
  defp public_reason(:harness_not_found), do: "Benchmark harness not found"
  defp public_reason(:capsule_version_not_found), do: "Benchmark capsule version not found"

  defp public_reason(:capsule_owner_required),
    do: "Only the capsule owner can change this capsule"

  defp public_reason(:version_id_required), do: "Benchmark capsule version is required"
  defp public_reason(:seed_required), do: "Benchmark publication seed is required"
  defp public_reason(:parent_id_required), do: "Benchmark publication parent is required"
  defp public_reason(:notebook_source_required), do: "Benchmark publication content is required"

  defp public_reason(:publication_visibility_invalid),
    do: "Benchmark publication visibility is invalid"

  defp public_reason(:repeat_attempts_required), do: "Repeat attempts are required"
  defp public_reason(:benchmark_import_domain_required), do: "Benchmark import domain is required"
  defp public_reason(:capsule_version_retired), do: "This capsule version is retired"
  defp public_reason(:capsule_version_mismatch), do: "Attempt does not match the capsule version"

  defp public_reason(:input_bundle_sha256_mismatch),
    do: "Attempt input bundle does not match the capsule version"

  defp public_reason(:harness_bundle_hash_mismatch),
    do: "Attempt harness bundle does not match the harness"

  defp public_reason(:attempt_capsule_mismatch), do: "Validation does not match the attempt"
  defp public_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp public_reason(_reason), do: "Benchmark request failed"
end
