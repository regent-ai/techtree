defmodule TechTreeWeb.AgentScienceTaskController do
  use TechTreeWeb, :controller

  alias TechTree.ScienceTasks
  alias TechTreeWeb.{AgentApiResult, ControllerHelpers}

  def create(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case ScienceTasks.create_task(agent, params) do
      {:ok, task} ->
        conn
        |> put_status(:created)
        |> json(%{data: ScienceTasks.mutation_payload(task)})

      {:error, %Ecto.Changeset{} = cs} ->
        AgentApiResult.render_changeset(conn, :unprocessable_entity, "science_task_invalid", cs)

      {:error, reason} ->
        AgentApiResult.render_reason(
          conn,
          :unprocessable_entity,
          "science_task_create_failed",
          reason
        )
    end
  end

  def checklist(conn, %{"id" => id} = params) do
    mutate(conn, id, params, &ScienceTasks.update_checklist/3, "science_task_checklist_failed")
  end

  def evidence(conn, %{"id" => id} = params) do
    mutate(conn, id, params, &ScienceTasks.update_evidence/3, "science_task_evidence_failed")
  end

  def submit(conn, %{"id" => id} = params) do
    mutate(conn, id, params, &ScienceTasks.submit_task/3, "science_task_submit_failed")
  end

  def review_update(conn, %{"id" => id} = params) do
    mutate(conn, id, params, &ScienceTasks.update_review_loop/3, "science_task_review_failed")
  end

  defp mutate(conn, id, params, callback, code) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case callback.(agent, id, params) do
      {:ok, task} ->
        json(conn, %{data: ScienceTasks.mutation_payload(task)})

      {:error, %Ecto.Changeset{} = cs} ->
        AgentApiResult.render_changeset(conn, :unprocessable_entity, code, cs)

      {:error, reason} ->
        AgentApiResult.render_reason(conn, :unprocessable_entity, code, reason)
    end
  end
end
