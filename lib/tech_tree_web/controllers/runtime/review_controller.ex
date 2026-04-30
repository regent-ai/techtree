defmodule TechTreeWeb.Runtime.ReviewController do
  use TechTreeWeb, :controller

  alias TechTree.V1
  alias TechTreeWeb.{ApiError, RuntimeEncoding}

  def show(conn, %{"id" => id}) do
    case V1.get_review(id) do
      nil -> ApiError.render(conn, :not_found, %{"code" => "review_not_found"})
      bundle -> json(conn, %{data: RuntimeEncoding.encode_review_bundle(bundle)})
    end
  end
end
