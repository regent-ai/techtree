defmodule TechTreeWeb.Runtime.PublishController do
  use TechTreeWeb, :controller

  alias TechTree.V1
  alias TechTreeWeb.{ApiError, RuntimeEncoding}

  def compile_artifact(conn, params), do: compile(conn, "artifact", params)
  def compile_run(conn, params), do: compile(conn, "run", params)
  def compile_review(conn, params), do: compile(conn, "review", params)

  def pin(conn, params) do
    with {:ok, path} <- require_path(params),
         {:ok, payload} <- V1.pin_workspace(path) do
      json(conn, %{data: payload})
    else
      {:error, reason} -> render_error(conn, "pin_failed", reason)
    end
  end

  def prepare(conn, params) do
    with {:ok, path} <- require_path(params),
         {:ok, payload} <- V1.prepare_publish(path) do
      json(conn, %{data: payload})
    else
      {:error, reason} -> render_error(conn, "publish_prepare_failed", reason)
    end
  end

  def submit(conn, params) do
    case V1.submit_publish(params) do
      {:ok, node} -> conn |> put_status(:created) |> json(%{data: RuntimeEncoding.encode_node(node)})
      {:error, reason} -> render_error(conn, "publish_submit_failed", reason)
    end
  end

  defp compile(conn, node_type, params) do
    with {:ok, path} <- require_path(params),
         {:ok, payload} <- V1.compile(node_type, path, Map.get(params, "author")) do
      json(conn, %{data: payload})
    else
      {:error, reason} -> render_error(conn, "compile_failed", reason)
    end
  end

  defp require_path(%{"path" => path}) when is_binary(path) and path != "", do: {:ok, path}
  defp require_path(%{path: path}) when is_binary(path) and path != "", do: {:ok, path}
  defp require_path(_params), do: {:error, :path_required}

  defp render_error(conn, code, {:command_failed, _status, output}),
    do: ApiError.render(conn, :unprocessable_entity, %{code: code, message: output})

  defp render_error(conn, code, {:invalid_json, _message, output}),
    do: ApiError.render(conn, :unprocessable_entity, %{code: code, message: output})

  defp render_error(conn, code, :path_required),
    do: ApiError.render(conn, :unprocessable_entity, %{code: code, message: "path is required"})

  defp render_error(conn, code, reason),
    do: ApiError.render(conn, :unprocessable_entity, %{code: code, message: inspect(reason)})
end
