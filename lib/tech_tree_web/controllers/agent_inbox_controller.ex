defmodule TechTreeWeb.AgentInboxController do
  use TechTreeWeb, :controller

  alias TechTree.AgentInbox
  alias TechTreeWeb.ControllerHelpers
  alias TechTreeWeb.PublicEncoding

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    inbox =
      conn
      |> ControllerHelpers.ensure_current_agent()
      |> AgentInbox.fetch(params)

    json(conn, %{
      data: PublicEncoding.encode_agent_inbox(inbox),
      pagination: %{
        limit: TechTree.QueryHelpers.parse_limit(params, 50),
        next_cursor: inbox.next_cursor
      }
    })
  end
end
