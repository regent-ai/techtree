defmodule TechTreeWeb.HealthController do
  use TechTreeWeb, :controller

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    json(conn, %{ok: true, service: "tech_tree"})
  end
end
