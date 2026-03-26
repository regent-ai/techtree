defmodule TechTreeWeb.AgentBbhController do
  use TechTreeWeb, :controller

  alias TechTree.BBH
  alias TechTreeWeb.ApiError

  def next_assignment(conn, params) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.next_assignment(claims, params) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :assignment_not_available} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_assignment_not_available",
          message: "No BBH assignment is available for the requested split"
        })

      {:error, :capsule_inventory_empty} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_inventory_empty",
          message: "BBH capsule inventory is empty"
        })

      {:error, :invalid_split} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_invalid_split",
          message: "Invalid BBH split"
        })

      {:error, reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_assignment_failed",
          message: Exception.message(reason)
        })
    end
  end

  def select_assignment(conn, params) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.select_assignment(claims, params) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :capsule_not_found} ->
        ApiError.render_halted(conn, :not_found, %{
          code: "bbh_capsule_not_found",
          message: "BBH capsule not found"
        })

      {:error, :capsule_not_selectable} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_capsule_not_selectable",
          message: "This BBH capsule cannot be selected directly"
        })

      {:error, :capsule_inventory_empty} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_inventory_empty",
          message: "BBH capsule inventory is empty"
        })

      {:error, :invalid_split} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_invalid_split",
          message: "Invalid BBH split"
        })

      {:error, reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_assignment_failed",
          message: Exception.message(reason)
        })
    end
  end

  def create_run(conn, params) do
    case BBH.create_run(params) do
      {:ok, %{run: run}} ->
        json(conn, %{
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
        ApiError.render_halted(conn, :not_found, %{
          code: "bbh_capsule_not_found",
          message: "BBH capsule not found"
        })

      {:error, :assignment_ref_required} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_assignment_ref_required",
          message: "Benchmark and challenge runs require an assignment reference"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_run_invalid",
          message: "BBH run submission is invalid",
          details: %{errors: translate_errors(changeset)}
        })

      {:error, %ArgumentError{} = reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_run_invalid",
          message: Exception.message(reason)
        })

      {:error, reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_run_failed",
          message: inspect(reason)
        })
    end
  end

  def create_validation(conn, params) do
    case BBH.create_validation(params) do
      {:ok, validation} ->
        json(conn, %{
          data: %{
            validation_id: validation.validation_id,
            run_id: validation.run_id,
            result: validation.result
          }
        })

      {:error, :run_not_found} ->
        ApiError.render_halted(conn, :not_found, %{
          code: "bbh_run_not_found",
          message: "BBH run not found"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_validation_invalid",
          message: "BBH validation is invalid",
          details: %{errors: translate_errors(changeset)}
        })

      {:error, %ArgumentError{} = reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_validation_invalid",
          message: Exception.message(reason)
        })

      {:error, reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_validation_failed",
          message: inspect(reason)
        })
    end
  end

  def sync(conn, params) do
    run_ids = Map.get(params, "run_ids", [])

    if is_list(run_ids) do
      json(conn, %{data: BBH.sync_status(run_ids)})
    else
      ApiError.render_halted(conn, :unprocessable_entity, %{
        code: "bbh_sync_invalid",
        message: "run_ids must be a list"
      })
    end
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
