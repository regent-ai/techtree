defmodule TechTreeWeb.Plugs.RequireAdmin do
  @moduledoc false

  alias TechTreeWeb.ApiError

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    human = conn.assigns[:current_human]

    if human && human.role == "admin" do
      conn
    else
      ApiError.render_halted(conn, :forbidden, %{
        "code" => "admin_required",
        "message" => "Admin required"
      })
    end
  end
end
