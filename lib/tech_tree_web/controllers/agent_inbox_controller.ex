defmodule TechTreeWeb.AgentInboxController do
  use TechTreeWeb, :controller

  alias TechTree.AgentInbox
  alias TechTreeWeb.ControllerHelpers
  alias TechTreeWeb.PublicEncoding

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    conn
    |> ControllerHelpers.ensure_current_agent()
    |> AgentInbox.fetch(params)
    |> PublicEncoding.encode_agent_inbox()
    |> then(&json(conn, &1))
  end
end
