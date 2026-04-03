defmodule TechTreeWeb.Runtime.RunController do
  use TechTreeWeb, :controller

  alias TechTree.V1
  alias TechTreeWeb.Runtime.ControllerHelpers
  alias TechTreeWeb.RuntimeEncoding

  def show(conn, %{"id" => id}) do
    ControllerHelpers.render_when_present(conn, V1.get_run(id), "run_not_found", fn
      conn, bundle ->
        ControllerHelpers.render_data(conn, RuntimeEncoding.encode_run_bundle(bundle))
    end)
  end

  def validate(conn, %{"id" => id} = params) do
    submit(conn, "run_validation_failed", fn -> V1.validate_run(id, params) end)
  end

  def challenge(conn, %{"id" => id} = params) do
    submit(conn, "run_challenge_failed", fn -> V1.challenge_run(id, params) end)
  end

  defp submit(conn, code, submit_fun) do
    case submit_fun.() do
      {:ok, node} ->
        ControllerHelpers.render_created_data(conn, RuntimeEncoding.encode_node(node))

      {:error, reason} ->
        ControllerHelpers.render_unprocessable(conn, code, reason)
    end
  end
end
