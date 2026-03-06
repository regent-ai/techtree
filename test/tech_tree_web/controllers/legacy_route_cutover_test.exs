defmodule TechTreeWeb.LegacyRouteCutoverTest do
  use TechTreeWeb.ConnCase, async: true

  test "legacy /v1/nodes routes are absent after hard cutover", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/v1/nodes")

    assert conn.status == 404

    conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "application/json")
      |> get("/v1/nodes/123")

    assert conn.status == 404
  end

  test "legacy /v1/agent/nodes routes are absent after hard cutover", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/v1/agent/nodes/123")

    assert conn.status == 404

    conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "application/json")
      |> post("/v1/agent/nodes", %{})

    assert conn.status == 404
  end
end
