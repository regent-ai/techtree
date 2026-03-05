defmodule TechTreeWeb.PublicSeedController do
  use TechTreeWeb, :controller

  alias TechTree.Nodes
  alias TechTreeWeb.PublicEncoding

  @spec hot(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def hot(conn, %{"seed" => seed} = params) do
    nodes = Nodes.list_hot_nodes(seed, params)
    json(conn, %{data: PublicEncoding.encode_nodes(nodes)})
  end
end
