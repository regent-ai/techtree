defmodule TechTreeWeb.Runtime.PublishController do
  use TechTreeWeb, :controller

  alias TechTree.V1
  alias TechTreeWeb.Runtime.ControllerHelpers
  alias TechTreeWeb.RuntimeEncoding

  def compile_artifact(conn, params), do: compile(conn, "artifact", params)
  def compile_run(conn, params), do: compile(conn, "run", params)
  def compile_review(conn, params), do: compile(conn, "review", params)

  def pin(conn, params) do
    with {:ok, path} <- require_path(params),
         {:ok, payload} <- V1.pin_workspace(path) do
      ControllerHelpers.render_data(conn, payload)
    else
      {:error, reason} -> ControllerHelpers.render_unprocessable(conn, "pin_failed", reason)
    end
  end

  def prepare(conn, params) do
    with {:ok, path} <- require_path(params),
         {:ok, payload} <- V1.prepare_publish(path) do
      ControllerHelpers.render_data(conn, payload)
    else
      {:error, reason} ->
        ControllerHelpers.render_unprocessable(conn, "publish_prepare_failed", reason)
    end
  end

  def submit(conn, params) do
    case V1.submit_publish(params) do
      {:ok, node} ->
        ControllerHelpers.render_created_data(conn, RuntimeEncoding.encode_node(node))

      {:error, reason} ->
        ControllerHelpers.render_unprocessable(conn, "publish_submit_failed", reason)
    end
  end

  defp compile(conn, node_type, params) do
    with {:ok, path} <- require_path(params),
         {:ok, payload} <- V1.compile(node_type, path, Map.get(params, "author")) do
      ControllerHelpers.render_data(conn, payload)
    else
      {:error, reason} -> ControllerHelpers.render_unprocessable(conn, "compile_failed", reason)
    end
  end

  defp require_path(%{"path" => path}) when is_binary(path) and path != "", do: {:ok, path}
  defp require_path(%{path: path}) when is_binary(path) and path != "", do: {:ok, path}
  defp require_path(_params), do: {:error, :path_required}
end
