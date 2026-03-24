defmodule TechTreeWeb.AgentOpportunitiesController do
  use TechTreeWeb, :controller

  alias TechTree.Opportunities
  alias TechTreeWeb.ControllerHelpers
  alias TechTreeWeb.PublicEncoding

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    conn
    |> ControllerHelpers.ensure_current_agent()
    |> Opportunities.list_for_agent(params)
    |> PublicEncoding.encode_opportunities()
    |> then(&json(conn, %{opportunities: &1}))
  end
end
