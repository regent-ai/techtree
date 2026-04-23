defmodule TechTreeWeb.AgentBbhController do
  use TechTreeWeb, :controller

  alias TechTree.BBH
  alias TechTreeWeb.AgentApiResult

  def next_assignment(conn, params) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.next_assignment(claims, params) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :assignment_not_available} ->
        invalid(
          conn,
          "bbh_assignment_not_available",
          "No BBH assignment is available for the requested split"
        )

      {:error, :capsule_inventory_empty} ->
        invalid(conn, "bbh_inventory_empty", "BBH capsule inventory is empty")

      {:error, :invalid_split} ->
        invalid(conn, "bbh_invalid_split", "Invalid BBH split")

      {:error, reason} ->
        invalid(conn, "bbh_assignment_failed", Exception.message(reason))
    end
  end

  def select_assignment(conn, params) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.select_assignment(claims, params) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :capsule_not_found} ->
        not_found(conn, "bbh_capsule_not_found", "BBH capsule not found")

      {:error, :capsule_not_selectable} ->
        invalid(
          conn,
          "bbh_capsule_not_selectable",
          "This BBH capsule cannot be selected directly"
        )

      {:error, :capsule_inventory_empty} ->
        invalid(conn, "bbh_inventory_empty", "BBH capsule inventory is empty")

      {:error, :invalid_split} ->
        invalid(conn, "bbh_invalid_split", "Invalid BBH split")

      {:error, reason} ->
        invalid(conn, "bbh_assignment_failed", Exception.message(reason))
    end
  end

  def create_run(conn, params) do
    case BBH.create_run(params) do
      {:ok, %{run: run}} ->
        conn
        |> put_status(:created)
        |> json(%{
          data: %{
            run_id: run.run_id,
            status: run.status,
            score: %{
              raw: run.raw_score,
              normalized: run.normalized_score
            },
            validation_state: run.status,
            public_run_path: "/bbh/runs/#{run.run_id}"
          }
        })

      {:error, :capsule_not_found} ->
        not_found(conn, "bbh_capsule_not_found", "BBH capsule not found")

      {:error, :assignment_ref_required} ->
        invalid(
          conn,
          "bbh_assignment_ref_required",
          "Benchmark and challenge runs require an assignment reference"
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        AgentApiResult.render_changeset_errors(
          conn,
          :unprocessable_entity,
          "bbh_run_invalid",
          "BBH run submission is invalid",
          changeset
        )

      {:error, %ArgumentError{} = reason} ->
        invalid(conn, "bbh_run_invalid", Exception.message(reason))

      {:error, reason} ->
        invalid(conn, "bbh_run_failed", inspect(reason))
    end
  end

  def create_validation(conn, params) do
    case BBH.create_validation(params) do
      {:ok, validation} ->
        conn
        |> put_status(:created)
        |> json(%{
          data: %{
            validation_id: validation.validation_id,
            run_id: validation.run_id,
            result: validation.result
          }
        })

      {:error, :run_not_found} ->
        not_found(conn, "bbh_run_not_found", "BBH run not found")

      {:error, %Ecto.Changeset{} = changeset} ->
        AgentApiResult.render_changeset_errors(
          conn,
          :unprocessable_entity,
          "bbh_validation_invalid",
          "BBH validation is invalid",
          changeset
        )

      {:error, %ArgumentError{} = reason} ->
        invalid(conn, "bbh_validation_invalid", Exception.message(reason))

      {:error, reason} ->
        invalid(conn, "bbh_validation_failed", inspect(reason))
    end
  end

  def sync(conn, params) do
    case Map.fetch(params, "run_ids") do
      {:ok, run_ids} when is_list(run_ids) ->
        json(conn, %{data: BBH.sync_status(run_ids)})

      _ ->
        invalid(conn, "bbh_sync_invalid", "run_ids must be a list")
    end
  end

  defp not_found(conn, code, message) do
    AgentApiResult.render_message(conn, :not_found, code, message)
  end

  defp invalid(conn, code, message) do
    AgentApiResult.render_message(conn, :unprocessable_entity, code, message)
  end
end
