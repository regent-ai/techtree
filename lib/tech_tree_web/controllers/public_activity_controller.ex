defmodule TechTreeWeb.PublicActivityController do
  use TechTreeWeb, :controller

  alias TechTree.Activity
  alias TechTreeWeb.PublicEncoding

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    events = Activity.list_public_events(params)
    json(conn, %{data: PublicEncoding.encode_activity_events(events)})
  end
end
