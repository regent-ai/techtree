defmodule TechTreeWeb.ScienceTaskController do
  use TechTreeWeb, :controller

  alias TechTree.ScienceTasks
  alias TechTreeWeb.ApiError

  def index(conn, params) do
    with {:ok, _stage} <- ScienceTasks.normalize_stage(params["stage"]) do
      tasks =
        params
        |> ScienceTasks.list_public_tasks()
        |> Enum.map(&ScienceTasks.encode_summary/1)

      json(conn, %{data: tasks})
    else
      {:error, :science_task_invalid_stage} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{code: "invalid_science_task_stage"})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, task} <- ScienceTasks.get_public_task(id) do
      json(conn, %{data: ScienceTasks.encode_detail(task)})
    else
      {:error, :science_task_invalid_id} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{code: "invalid_science_task_id"})

      {:error, :science_task_not_found} ->
        ApiError.render_halted(conn, :not_found, %{code: "science_task_not_found"})
    end
  end
end
