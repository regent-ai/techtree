defmodule TechTreeWeb.RawBodyReader do
  @moduledoc false

  def read_body(conn, opts) do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn, opts) do
      conn = Plug.Conn.assign(conn, :raw_body, body)
      {:ok, body, conn}
    end
  end
end
