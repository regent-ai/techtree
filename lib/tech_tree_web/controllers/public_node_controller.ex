defmodule TechTreeWeb.PublicNodeController do
  use TechTreeWeb, :controller

  alias TechTree.Nodes
  alias TechTree.Comments
  alias TechTreeWeb.ApiError
  alias TechTreeWeb.PublicEncoding

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    nodes = Nodes.list_public_nodes(params)
    json(conn, %{data: PublicEncoding.encode_nodes(nodes)})
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    with {:ok, normalized_id} <- parse_id(id),
         {:ok, node} <- fetch_public_node(normalized_id) do
      json(conn, %{data: PublicEncoding.encode_node(node)})
    else
      {:error, :invalid_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})

      :error ->
        ApiError.render(conn, :not_found, %{code: "node_not_found"})
    end
  end

  @spec children(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def children(conn, %{"id" => id} = params) do
    case parse_id(id) do
      {:ok, normalized_id} ->
        children = Nodes.list_public_children(normalized_id, params)
        json(conn, %{data: PublicEncoding.encode_nodes(children)})

      {:error, :invalid_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})
    end
  end

  @spec sidelinks(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sidelinks(conn, %{"id" => id}) do
    case parse_id(id) do
      {:ok, normalized_id} ->
        sidelinks = Nodes.list_tagged_edges(normalized_id)
        json(conn, %{data: PublicEncoding.encode_tag_edges(sidelinks)})

      {:error, :invalid_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})
    end
  end

  @spec comments(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def comments(conn, %{"id" => id} = params) do
    case parse_id(id) do
      {:ok, normalized_id} ->
        comments = Comments.list_public_for_node(normalized_id, params)
        json(conn, %{data: PublicEncoding.encode_comments(comments)})

      {:error, :invalid_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})
    end
  end

  @spec fetch_public_node(integer() | String.t()) :: {:ok, TechTree.Nodes.Node.t()} | :error
  defp fetch_public_node(id) do
    {:ok, Nodes.get_public_node!(id)}
  rescue
    Ecto.NoResultsError -> :error
  end

  @spec parse_id(integer() | String.t()) :: {:ok, integer()} | {:error, :invalid_id}
  defp parse_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id(_value), do: {:error, :invalid_id}
end
