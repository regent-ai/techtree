defmodule TechTreeWeb.InternalV1Controller do
  use TechTreeWeb, :controller

  alias TechTree.V1
  alias TechTreeWeb.{ApiError, RuntimeEncoding}

  @spec ingest_published_node(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ingest_published_node(conn, params) do
    case V1.ingest_published_event(params) do
      {:ok, node} ->
        conn
        |> put_status(:created)
        |> json(%{data: RuntimeEncoding.encode_node(node)})

      :not_found ->
        ApiError.render(conn, :unprocessable_entity, %{
          "code" => "publish_receipt_not_found",
          "message" => "publish receipt is not available yet"
        })

      {:error, _reason} ->
        ApiError.render(conn, :unprocessable_entity, %{
          "code" => "publish_ingest_failed"
        })
    end
  end
end
