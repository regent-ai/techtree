defmodule TechTreeWeb.SearchController do
  use TechTreeWeb, :controller

  alias TechTree.Search
  alias TechTreeWeb.PublicEncoding

  action_fallback TechTreeWeb.FallbackController

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, %{"q" => q} = params) when is_binary(q) and byte_size(q) > 0 do
    results = Search.search(q, params)

    json(conn, %{
      data: PublicEncoding.encode_search_results(results),
      pagination: %{
        limit: results.limit,
        next_cursor: results.next_cursor
      }
    })
  end

  def index(_conn, _params) do
    {:error, :search_query_required}
  end
end
