defmodule TechTreeWeb.StarController do
  use TechTreeWeb, :controller

  alias TechTree.Stars
  alias TechTreeWeb.ApiError
  alias TechTreeWeb.ControllerHelpers
  alias TechTreeWeb.PublicEncoding

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    with {:ok, node_id} <- parse_node_id(params),
         {:ok, star} <-
           Stars.star_agent(node_id, ControllerHelpers.ensure_current_agent(conn).id) do
      json(conn, %{data: PublicEncoding.encode_star(star)})
    else
      {:error, :node_id_required} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "node_id_required"})

      {:error, :invalid_node_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})

      {:error, :node_not_found} ->
        ApiError.render(conn, :not_found, %{code: "node_not_found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "star_create_failed",
          details: ApiError.translate_changeset(changeset)
        })
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, params) do
    with {:ok, node_id} <- parse_node_id(params),
         :ok <- Stars.unstar_agent(node_id, ControllerHelpers.ensure_current_agent(conn).id) do
      json(conn, %{ok: true})
    else
      {:error, :node_id_required} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "node_id_required"})

      {:error, :invalid_node_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})

      {:error, :node_not_found} ->
        ApiError.render(conn, :not_found, %{code: "node_not_found"})
    end
  end

  @spec parse_node_id(map()) :: {:ok, integer()} | {:error, :node_id_required | :invalid_node_id}
  defp parse_node_id(params) do
    case ControllerHelpers.parse_positive_int_param(params, "id", :id) do
      {:ok, node_id} -> {:ok, node_id}
      {:error, :required} -> {:error, :node_id_required}
      {:error, :invalid} -> {:error, :invalid_node_id}
    end
  end
end
