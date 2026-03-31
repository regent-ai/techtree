defmodule TechTreeWeb.Runtime.SearchController do
  use TechTreeWeb, :controller

  alias TechTree.V1
  alias TechTreeWeb.RuntimeEncoding

  def index(conn, %{"q" => q}) when is_binary(q) do
    if byte_size(String.trim(q)) > 0 do
      json(conn, %{data: V1.search(q) |> RuntimeEncoding.encode_search_results()})
    else
      json(conn, %{data: []})
    end
  end

  def index(conn, _params), do: json(conn, %{data: []})
end
