defmodule TechTreeWeb.Runtime.PublishController do
  use TechTreeWeb, :controller

  alias TechTree.V1
  alias TechTreeWeb.Runtime.ControllerHelpers
  alias TechTreeWeb.RuntimeEncoding

  def submit(conn, params) do
    case V1.submit_publish(params) do
      {:ok, node} ->
        ControllerHelpers.render_created_data(conn, RuntimeEncoding.encode_node(node))

      {:error, reason} ->
        ControllerHelpers.render_unprocessable(conn, "publish_submit_failed", reason)
    end
  end
end
