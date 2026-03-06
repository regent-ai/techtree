defmodule TechTreeWeb.PublicNodeControllerTest do
  use TechTreeWeb.ConnCase, async: true

  test "show returns 404 json for non-public or missing node", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/v1/tree/nodes/999999999")
      |> json_response(404)

    assert %{"error" => %{"code" => "node_not_found"}} = response
  end

  test "sidelinks returns empty list for missing public node", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/v1/tree/nodes/999999999/sidelinks")
      |> json_response(200)

    assert %{"data" => []} = response
  end

  test "invalid node id returns 422 for node routes", %{conn: conn} do
    assert %{"error" => %{"code" => "invalid_node_id"}} =
             conn
             |> put_req_header("accept", "application/json")
             |> get("/v1/tree/nodes/not-an-id")
             |> json_response(422)

    assert %{"error" => %{"code" => "invalid_node_id"}} =
             conn
             |> put_req_header("accept", "application/json")
             |> get("/v1/tree/nodes/not-an-id/children")
             |> json_response(422)

    assert %{"error" => %{"code" => "invalid_node_id"}} =
             conn
             |> put_req_header("accept", "application/json")
             |> get("/v1/tree/nodes/not-an-id/sidelinks")
             |> json_response(422)

    assert %{"error" => %{"code" => "invalid_node_id"}} =
             conn
             |> put_req_header("accept", "application/json")
             |> get("/v1/tree/nodes/not-an-id/comments")
             |> json_response(422)
  end
end
