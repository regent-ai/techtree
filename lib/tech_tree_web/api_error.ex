defmodule TechTreeWeb.ApiError do
  @moduledoc false

  import Plug.Conn, only: [halt: 1, put_status: 2]
  import Phoenix.Controller, only: [json: 2]

  @spec render(Plug.Conn.t(), Plug.Conn.status(), map()) :: Plug.Conn.t()
  def render(conn, status, error_payload) when is_map(error_payload) do
    status_code = Plug.Conn.Status.code(status)

    conn
    |> put_status(status)
    |> json(%{error: stable_error(conn, status_code, error_payload)})
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

  defp stable_error(conn, status_code, payload) do
    code = Map.get(payload, :code) || Map.get(payload, "code") || "request_failed"

    %{
      code: code,
      product: "techtree",
      status: status_code,
      path: conn.request_path,
      request_id: request_id(conn),
      message: Map.get(payload, :message) || Map.get(payload, "message") || code,
      next_steps: Map.get(payload, :next_steps) || Map.get(payload, "next_steps")
    }
    |> maybe_put(:details, Map.get(payload, :details) || Map.get(payload, "details"))
    |> maybe_put(
      :retry_after_ms,
      Map.get(payload, :retry_after_ms) || Map.get(payload, "retry_after_ms")
    )
  end

  defp request_id(conn) do
    conn
    |> Plug.Conn.get_resp_header("x-request-id")
    |> List.first()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
