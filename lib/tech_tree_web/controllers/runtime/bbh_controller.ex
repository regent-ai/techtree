defmodule TechTreeWeb.Runtime.BbhController do
  use TechTreeWeb, :controller

  alias TechTree.V1

  def leaderboard(conn, params) do
    json(conn, %{data: V1.bbh_leaderboard(params)})
  end

  def sync(conn, params) do
    json(conn, %{data: V1.bbh_sync_status(params)})
  end
end
