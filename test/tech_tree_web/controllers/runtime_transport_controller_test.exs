defmodule TechTreeWeb.RuntimeTransportControllerTest do
  use TechTreeWeb.ConnCase, async: true

  test "GET /v1/runtime/transport exposes backend transport state", %{conn: conn} do
    assert %{
             "data" => %{
               "mode" => "local_only",
               "ready" => false,
               "peer_count" => 0,
               "subscriptions" => [],
               "origin_node_id" => origin_node_id
             }
           } =
             conn
             |> put_req_header("accept", "application/json")
             |> get("/v1/runtime/transport")
             |> json_response(200)

    assert is_binary(origin_node_id)
    assert origin_node_id != ""
  end
end
