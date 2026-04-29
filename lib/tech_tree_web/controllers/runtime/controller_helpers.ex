defmodule TechTreeWeb.Runtime.ControllerHelpers do
  @moduledoc false

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2]

  alias TechTreeWeb.ApiError

  def render_data(conn, data), do: json(conn, %{data: data})

  def render_created_data(conn, data) do
    conn
    |> put_status(:created)
    |> json(%{data: data})
  end

  def render_not_found(conn, code), do: ApiError.render(conn, :not_found, %{code: code})

  def render_when_present(conn, nil, not_found_code, _render_fun),
    do: render_not_found(conn, not_found_code)

  def render_when_present(conn, value, _not_found_code, render_fun),
    do: render_fun.(conn, value)

  def render_unprocessable(conn, code, reason, opts \\ []) do
    case Keyword.get(opts, :message, default_message(reason)) do
      :omit ->
        ApiError.render(conn, :unprocessable_entity, %{code: code})

      message ->
        ApiError.render(conn, :unprocessable_entity, %{code: code, message: message})
    end
  end

  defp default_message({:command_failed, _status, _output}), do: "runtime command failed"
  defp default_message({:invalid_json, _message, _output}), do: "runtime response was invalid"
  defp default_message(:invalid_review_submission), do: "invalid review submission"
  defp default_message(:invalid_submission), do: "invalid submission"
  defp default_message(_reason), do: "request could not be completed"
end
