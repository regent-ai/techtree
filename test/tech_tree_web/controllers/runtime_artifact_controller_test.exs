defmodule TechTreeWeb.RuntimeArtifactControllerTest do
  use TechTreeWeb.ConnCase, async: true

  alias TechTree.V1Fixtures

  test "GET /v1/runtime/artifacts/:id returns canonical artifact metadata and bundle", %{
    conn: conn
  } do
    %{artifact: artifact, run: run} =
      V1Fixtures.insert_bbh_bundle!(%{display_name: "artifact-meta"})

    response =
      conn
      |> get("/v1/runtime/artifacts/#{artifact.id}")
      |> json_response(200)

    assert %{
             "data" => %{
               "node" => %{"id" => node_id},
               "artifact" => %{"id" => artifact_id},
               "parents" => [],
               "children" => [],
               "runs" => [%{"id" => run_id}]
             }
           } = response

    assert node_id == artifact.id
    assert artifact_id == artifact.id
    assert run_id == run.id
  end

  test "GET /v1/runtime/artifacts/:id/parents and children return empty lists for standalone artifacts",
       %{conn: conn} do
    %{artifact: artifact} = V1Fixtures.insert_bbh_bundle!(%{display_name: "artifact-edges"})

    assert %{"data" => []} =
             conn
             |> get("/v1/runtime/artifacts/#{artifact.id}/parents")
             |> json_response(200)

    assert %{"data" => []} =
             conn
             |> get("/v1/runtime/artifacts/#{artifact.id}/children")
             |> json_response(200)
  end

  test "GET /v1/runtime/artifacts/:id returns not found for missing artifact", %{conn: conn} do
    missing_id = "0x" <> String.duplicate("f", 64)

    assert %{"error" => %{"code" => "artifact_not_found"}} =
             conn
             |> get("/v1/runtime/artifacts/#{missing_id}")
             |> json_response(404)
  end
end
