defmodule TechTreeWeb.Runtime.RunController do
  use TechTreeWeb, :controller

  alias TechTree.V1
  alias TechTreeWeb.{ApiError, RuntimeEncoding}

  def show(conn, %{"id" => id}) do
    case V1.get_run(id) do
      nil -> ApiError.render(conn, :not_found, %{code: "run_not_found"})
      bundle -> json(conn, %{data: RuntimeEncoding.encode_run_bundle(bundle)})
    end
  end

  def validate(conn, %{"id" => id} = params) do
    case V1.validate_run(id, params) do
      {:ok, node} -> conn |> put_status(:created) |> json(%{data: RuntimeEncoding.encode_node(node)})
      {:error, reason} -> render_error(conn, "run_validation_failed", reason)
    end
  end

  def challenge(conn, %{"id" => id} = params) do
    case V1.challenge_run(id, params) do
      {:ok, node} -> conn |> put_status(:created) |> json(%{data: RuntimeEncoding.encode_node(node)})
      {:error, reason} -> render_error(conn, "run_challenge_failed", reason)
    end
  end

  defp render_error(conn, code, {:command_failed, _status, output}),
    do: ApiError.render(conn, :unprocessable_entity, %{code: code, message: output})

  defp render_error(conn, code, :invalid_review_submission),
    do:
      ApiError.render(conn, :unprocessable_entity, %{
        code: code,
        message: "invalid review submission"
      })

  defp render_error(conn, code, reason),
    do: ApiError.render(conn, :unprocessable_entity, %{code: code, message: inspect(reason)})
end
