defmodule TechTreeWeb.FallbackController do
  @moduledoc false

  use TechTreeWeb, :controller

  alias TechTreeWeb.ApiError

  def call(conn, {:error, :not_found}) do
    ApiError.render_halted(conn, :not_found, %{"code" => "not_found"})
  end

  def call(conn, {:error, :search_query_required}) do
    ApiError.render_halted(conn, :unprocessable_entity, %{
      "code" => "search_query_required",
      "message" => "Add a search term before searching."
    })
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    ApiError.render_halted(conn, :unprocessable_entity, %{
      "code" => "invalid_request",
      "details" => ApiError.translate_changeset(changeset)
    })
  end

  def call(conn, {:error, %ArgumentError{} = error}) do
    ApiError.render_halted(conn, :unprocessable_entity, %{
      "code" => "invalid_request",
      "message" => Exception.message(error)
    })
  end

  def call(conn, {:error, reason}) when is_atom(reason) do
    ApiError.render_halted(conn, :unprocessable_entity, %{"code" => Atom.to_string(reason)})
  end
end
