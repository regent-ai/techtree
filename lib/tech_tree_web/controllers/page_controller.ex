defmodule TechTreeWeb.PageController do
  use TechTreeWeb, :controller

  def home(conn, _params) do
    privy_app_id =
      :tech_tree
      |> Application.get_env(:privy, [])
      |> Keyword.get(:app_id, "")

    render(conn, :home, privy_app_id: privy_app_id)
  end
end
