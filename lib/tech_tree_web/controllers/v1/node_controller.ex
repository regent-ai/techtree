defmodule TechTreeWeb.V1.NodeController do
  use TechTreeWeb, :controller

  alias TechTree.V1
  alias TechTreeWeb.{ApiError, V1Encoding}

  def show(conn, %{"id" => id}) do
    case V1.get_node(id) do
      nil -> ApiError.render(conn, :not_found, %{code: "node_not_found"})
      node -> json(conn, %{data: V1Encoding.encode_node(node)})
    end
  end
end
