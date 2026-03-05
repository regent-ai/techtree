defmodule TechTreeWeb.SearchController do
  use TechTreeWeb, :controller

  alias TechTree.Search
  alias TechTreeWeb.PublicEncoding

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, %{"q" => q} = params) when is_binary(q) and byte_size(q) > 0 do
    results = Search.search(q, params)
    json(conn, %{data: PublicEncoding.encode_search_results(results)})
  end

  def index(conn, _params) do
    json(conn, %{data: %{nodes: [], comments: []}})
  end
end
