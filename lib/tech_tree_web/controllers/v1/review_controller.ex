defmodule TechTreeWeb.V1.ReviewController do
  use TechTreeWeb, :controller

  alias TechTree.V1
  alias TechTreeWeb.{ApiError, V1Encoding}

  def show(conn, %{"id" => id}) do
    case V1.get_review(id) do
      nil -> ApiError.render(conn, :not_found, %{code: "review_not_found"})
      bundle -> json(conn, %{data: V1Encoding.encode_review_bundle(bundle)})
    end
  end
end
