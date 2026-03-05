defmodule TechTreeWeb.ApiError do
  @moduledoc false

  import Plug.Conn, only: [halt: 1, put_status: 2]
  import Phoenix.Controller, only: [json: 2]

  @spec render(Plug.Conn.t(), Plug.Conn.status(), map()) :: Plug.Conn.t()
  def render(conn, status, error_payload) when is_map(error_payload) do
    conn
    |> put_status(status)
    |> json(%{error: error_payload})
  end

  @spec render_halted(Plug.Conn.t(), Plug.Conn.status(), map()) :: Plug.Conn.t()
  def render_halted(conn, status, error_payload) do
    conn
    |> render(status, error_payload)
    |> halt()
  end

  @spec translate_changeset(Ecto.Changeset.t()) :: map()
  def translate_changeset(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
