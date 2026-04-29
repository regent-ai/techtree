defmodule TechTreeWeb.AgentOpportunitiesController do
  use TechTreeWeb, :controller

  alias TechTree.Opportunities
  alias TechTreeWeb.ControllerHelpers
  alias TechTreeWeb.PublicEncoding

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    opportunities =
      conn
      |> ControllerHelpers.ensure_current_agent()
      |> Opportunities.list_for_agent(params)

    json(
      conn,
      ControllerHelpers.paginated(
        %{opportunities: PublicEncoding.encode_opportunities(opportunities)},
        params,
        opportunities,
        20,
        :node_id
      )
    )
  end
end
