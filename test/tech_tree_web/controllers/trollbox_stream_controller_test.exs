defmodule TechTreeWeb.TrollboxStreamControllerTest do
  use TechTreeWeb.ConnCase, async: true

  import TechTree.PhaseDApiSupport

  test "public stream rejects the agent room alias", %{conn: conn} do
    assert %{"error" => %{"code" => "invalid_trollbox_room"}} =
             conn
             |> put_req_header("accept", "application/json")
             |> get("/v1/runtime/transport/stream", %{"room" => "agent"})
             |> json_response(422)
  end

  test "agent stream rejects the webapp room alias", %{conn: conn} do
    assert %{"error" => %{"code" => "invalid_trollbox_room"}} =
             conn
             |> with_siwa_headers()
             |> get("/v1/agent/runtime/transport/stream", %{"room" => "webapp"})
             |> json_response(422)
  end
end
