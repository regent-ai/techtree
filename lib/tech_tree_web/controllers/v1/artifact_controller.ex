defmodule TechTreeWeb.V1.ArtifactController do
  use TechTreeWeb, :controller

  alias TechTree.V1
  alias TechTreeWeb.{ApiError, V1Encoding}

  def show(conn, %{"id" => id}) do
    case V1.get_artifact(id) do
      nil -> ApiError.render(conn, :not_found, %{code: "artifact_not_found"})
      bundle -> json(conn, %{data: V1Encoding.encode_artifact_bundle(bundle)})
    end
  end

  def parents(conn, %{"id" => id}) do
    if V1.get_artifact(id) do
      json(conn, %{
        data: Enum.map(V1.list_artifact_parents(id), &V1Encoding.encode_node(&1.parent))
      })
    else
      ApiError.render(conn, :not_found, %{code: "artifact_not_found"})
    end
  end

  def children(conn, %{"id" => id}) do
    if V1.get_artifact(id) do
      json(conn, %{
        data: Enum.map(V1.list_artifact_children(id), &V1Encoding.encode_node(&1.child))
      })
    else
      ApiError.render(conn, :not_found, %{code: "artifact_not_found"})
    end
  end

  def runs(conn, %{"id" => id}) do
    if V1.get_artifact(id) do
      json(conn, %{
        data: Enum.map(V1.list_artifact_runs(id), &V1Encoding.encode_run_summary/1)
      })
    else
      ApiError.render(conn, :not_found, %{code: "artifact_not_found"})
    end
  end

  def challenge(conn, %{"id" => id} = params) do
    case V1.challenge_artifact(id, params) do
      {:ok, node} -> conn |> put_status(:created) |> json(%{data: V1Encoding.encode_node(node)})
      {:error, reason} -> render_error(conn, reason)
    end
  end

  defp render_error(conn, {:command_failed, _status, output}),
    do:
      ApiError.render(conn, :unprocessable_entity, %{code: "core_command_failed", message: output})

  defp render_error(conn, {:invalid_json, _message, output}),
    do:
      ApiError.render(conn, :unprocessable_entity, %{code: "core_invalid_json", message: output})

  defp render_error(conn, :invalid_review_submission),
    do: ApiError.render(conn, :unprocessable_entity, %{code: "invalid_review_submission"})

  defp render_error(conn, :invalid_submission),
    do: ApiError.render(conn, :unprocessable_entity, %{code: "invalid_submission"})

  defp render_error(conn, reason),
    do:
      ApiError.render(conn, :unprocessable_entity, %{
        code: "artifact_challenge_failed",
        message: inspect(reason)
      })
end
