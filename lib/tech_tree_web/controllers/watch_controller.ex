defmodule TechTreeWeb.WatchController do
  use TechTreeWeb, :controller

  alias TechTreeWeb.ApiError
  alias TechTreeWeb.ControllerHelpers
  alias TechTreeWeb.PublicEncoding
  alias TechTree.Nodes.Node
  alias TechTree.Repo
  alias TechTree.Watches

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    watches =
      conn
      |> ControllerHelpers.ensure_current_agent()
      |> then(&Watches.list_agent_watches(&1.id))

    json(conn, %{data: PublicEncoding.encode_watches(watches)})
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    with {:ok, node_id} <- parse_node_id(params),
         {:ok, _node} <- fetch_node(node_id),
         {:ok, watch} <-
           Watches.watch_agent(node_id, ControllerHelpers.ensure_current_agent(conn).id) do
      json(conn, %{data: PublicEncoding.encode_watch(watch)})
    else
      {:error, :node_not_found} ->
        ApiError.render(conn, :not_found, %{code: "node_not_found"})

      {:error, :node_id_required} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "node_id_required"})

      {:error, :invalid_node_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "watch_create_failed",
          details: ApiError.translate_changeset(changeset)
        })

      {:error, reason} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "watch_create_failed",
          message: inspect(reason)
        })
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, params) do
    with {:ok, node_id} <- parse_node_id(params),
         {:ok, _node} <- fetch_node(node_id),
         :ok <- Watches.unwatch_agent(node_id, ControllerHelpers.ensure_current_agent(conn).id) do
      json(conn, %{ok: true})
    else
      {:error, :node_not_found} ->
        ApiError.render(conn, :not_found, %{code: "node_not_found"})

      {:error, :node_id_required} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "node_id_required"})

      {:error, :invalid_node_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})
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

  @spec fetch_node(integer()) :: {:ok, Node.t()} | {:error, :node_not_found}
  defp fetch_node(node_id) do
    case Repo.get(Node, node_id) do
      nil -> {:error, :node_not_found}
      %Node{} = node -> {:ok, node}
    end
  end
end
