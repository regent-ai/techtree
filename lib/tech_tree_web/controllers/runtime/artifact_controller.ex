defmodule TechTreeWeb.Runtime.ArtifactController do
  use TechTreeWeb, :controller

  alias TechTree.V1
  alias TechTreeWeb.Runtime.ControllerHelpers
  alias TechTreeWeb.RuntimeEncoding

  def show(conn, %{"id" => id}) do
    ControllerHelpers.render_when_present(conn, V1.get_artifact(id), "artifact_not_found", fn
      conn, bundle ->
        ControllerHelpers.render_data(conn, RuntimeEncoding.encode_artifact_bundle(bundle))
    end)
  end

  def parents(conn, %{"id" => id}) do
    ControllerHelpers.render_when_present(conn, V1.get_artifact(id), "artifact_not_found", fn
      conn, _artifact ->
        ControllerHelpers.render_data(
          conn,
          Enum.map(V1.list_artifact_parents(id), &RuntimeEncoding.encode_node(&1.parent))
        )
    end)
  end

  def children(conn, %{"id" => id}) do
    ControllerHelpers.render_when_present(conn, V1.get_artifact(id), "artifact_not_found", fn
      conn, _artifact ->
        ControllerHelpers.render_data(
          conn,
          Enum.map(V1.list_artifact_children(id), &RuntimeEncoding.encode_node(&1.child))
        )
    end)
  end

  def runs(conn, %{"id" => id}) do
    ControllerHelpers.render_when_present(conn, V1.get_artifact(id), "artifact_not_found", fn
      conn, _artifact ->
        ControllerHelpers.render_data(
          conn,
          Enum.map(V1.list_artifact_runs(id), &RuntimeEncoding.encode_run_summary/1)
        )
    end)
  end

  def challenge(conn, %{"id" => id} = params) do
    case V1.challenge_artifact(id, params) do
      {:ok, node} ->
        ControllerHelpers.render_created_data(conn, RuntimeEncoding.encode_node(node))

      {:error, reason} ->
        ControllerHelpers.render_unprocessable(
          conn,
          "artifact_challenge_failed",
          reason,
          message: artifact_error_message(reason)
        )
    end
  end

  defp artifact_error_message(reason)
       when reason in [:invalid_review_submission, :invalid_submission],
       do: :omit

  defp artifact_error_message(_reason), do: nil
end
