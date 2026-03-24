defmodule TechTreeWeb.V1RunMetadataTest do
  use TechTreeWeb.ConnCase, async: true

  alias TechTree.V1Fixtures

  test "GET /api/v1/runs/:id returns canonical run metadata and artifact bundle", %{conn: conn} do
    %{run: run, artifact: artifact} = V1Fixtures.insert_bbh_bundle!(%{display_name: "run-meta"})

    response =
      conn
      |> get("/api/v1/runs/#{run.id}")
      |> json_response(200)

    assert %{
             "data" => %{
               "run" => %{
                 "id" => run_id,
                 "executor_harness_kind" => "hermes",
                 "executor_harness_profile" => "bbh",
                 "origin_kind" => "local",
                 "origin_transport" => nil,
                 "origin_session_id" => session
               },
               "artifact" => %{
                 "node" => %{"id" => artifact_node_id},
                 "artifact" => %{"id" => artifact_id},
                 "runs" => [%{"id" => run_run_id, "origin_session_id" => run_session}]
               }
             }
           } = response

    assert run_id == run.id
    assert run_run_id == run.id
    assert run_session == session

    assert artifact_node_id == artifact.id
    assert artifact_id == artifact.id
  end

  test "GET /api/v1/artifacts/:id/runs returns normalized run summaries", %{conn: conn} do
    %{artifact: artifact, run: run} =
      V1Fixtures.insert_bbh_bundle!(%{display_name: "artifact-runs"})

    assert %{
             "data" => [
               %{
                 "id" => run_id,
                 "executor_id" => "genome:artifact-runs",
                 "executor_harness_kind" => "hermes",
                 "executor_harness_profile" => "bbh",
                 "origin_kind" => "local",
                 "origin_transport" => nil,
                 "origin_session_id" => session
               }
             ]
           } =
             conn
             |> get("/api/v1/artifacts/#{artifact.id}/runs")
             |> json_response(200)

    assert run_id == run.id

    assert is_binary(session) and session != ""
  end

  test "GET /api/v1/reviews/:id returns the run target with metadata", %{conn: conn} do
    %{review: review, run: run} = V1Fixtures.insert_bbh_bundle!(%{display_name: "review-meta"})

    assert %{
             "data" => %{
               "target" => %{
                 "id" => target_id,
                 "run" => %{
                   "executor_harness_kind" => "hermes",
                   "executor_harness_profile" => "bbh",
                   "origin_kind" => "local",
                   "origin_transport" => nil,
                   "origin_session_id" => session
                 }
               }
             }
           } =
             conn
             |> get("/api/v1/reviews/#{review.id}")
             |> json_response(200)

    assert target_id == run.id

    assert is_binary(session) and session != ""
  end

  test "GET /api/v1/search returns run metadata for run hits", %{conn: conn} do
    %{run: run} = V1Fixtures.insert_bbh_bundle!(%{display_name: "search-meta"})

    assert %{
             "data" => [
               %{
                 "id" => run_id,
                 "node_type" => "run",
                 "executor_id" => "genome:search-meta",
                 "executor_harness_kind" => "hermes",
                 "executor_harness_profile" => "bbh",
                 "origin_kind" => "local",
                 "origin_transport" => nil,
                 "origin_session_id" => session,
                 "run" => %{
                   "executor_harness_kind" => "hermes",
                   "executor_harness_profile" => "bbh",
                   "origin_kind" => "local",
                   "origin_transport" => nil,
                   "origin_session_id" => session
                 }
               }
             ]
           } =
             conn
             |> get("/api/v1/search", %{"q" => "genome:search-meta"})
             |> json_response(200)

    assert run_id == run.id

    assert is_binary(session) and session != ""
  end
end
