defmodule TechTreeWeb.PageController do
  use TechTreeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
