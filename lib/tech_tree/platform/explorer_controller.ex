defmodule TechTreeWeb.PlatformApi.ExplorerController do
  use TechTreeWeb, :controller

  alias TechTree.Platform

  def index(conn, _params) do
    json(conn, %{tiles: Platform.list_tiles_json()})
  end
end
