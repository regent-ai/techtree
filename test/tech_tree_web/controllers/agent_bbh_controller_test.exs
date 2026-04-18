defmodule TechTreeWeb.AgentBbhControllerTest do
  use TechTreeWeb.ConnCase, async: true

  import TechTreeWeb.TestSupport.SiwaIntegrationSupport

  alias TechTree.BBHFixtures
  alias TechTree.Repo
  alias TechTree.BBH.{Run, Validation}

  test "agent BBH write routes require SIWA headers", %{conn: conn} do
    assert %{"error" => %{"code" => "agent_auth_required"}} =
             conn
             |> post("/v1/agent/bbh/assignments/next", %{})
             |> json_response(401)

    assert %{"error" => %{"code" => "agent_auth_required"}} =
             conn
             |> post("/v1/agent/bbh/assignments/select", %{"capsule_id" => "capsule_123"})
             |> json_response(401)
  end

  test "POST /v1/agent/bbh/assignments/next returns the next climb capsule", %{conn: conn} do
    _capsule = BBHFixtures.insert_capsule!(%{split: "climb", assignment_policy: "auto_or_select"})

    response =
      conn
      |> with_siwa_headers([])
      |> post("/v1/agent/bbh/assignments/next", %{"split" => "climb"})
      |> json_response(200)

    assert %{
             "data" => %{
               "assignment_ref" => assignment_ref,
               "split" => "climb",
               "capsule" => %{"capsule_id" => capsule_id}
             }
           } = response

    assert is_binary(assignment_ref) and assignment_ref != ""
    assert is_binary(capsule_id) and capsule_id != ""
    assert response["data"]["capsule"]["title"]
    assert response["data"]["capsule"]["protocol_md"]

    assert get_in(response, ["data", "capsule", "execution_defaults", "solver", "kind"]) ==
             "skydiscover"

    assert get_in(response, [
             "data",
             "capsule",
             "execution_defaults",
             "solver",
             "search_algorithm"
           ]) ==
             "best_of_n"
  end

  test "POST /v1/agent/bbh/assignments/select returns a selected climb capsule", %{conn: conn} do
    capsule = BBHFixtures.insert_capsule!(%{split: "climb", assignment_policy: "auto_or_select"})

    response =
      conn
      |> with_siwa_headers([])
      |> post("/v1/agent/bbh/assignments/select", %{"capsule_id" => capsule.capsule_id})
      |> json_response(200)

    assert %{
             "data" => %{
               "assignment_ref" => assignment_ref,
               "split" => "climb",
               "capsule" => %{"capsule_id" => capsule_id}
             }
           } = response

    assert is_binary(assignment_ref) and assignment_ref != ""
    assert capsule_id == capsule.capsule_id
  end

  test "POST /v1/agent/bbh/assignments/select rejects visible operator capsules", %{conn: conn} do
    %{capsule: capsule} =
      BBHFixtures.insert_published_challenge_capsule!(%{
        title: "Read-only Challenge",
        assignment_policy: "operator"
      })

    assert %{"error" => %{"code" => "bbh_capsule_not_selectable"}} =
             conn
             |> with_siwa_headers([])
             |> post("/v1/agent/bbh/assignments/select", %{"capsule_id" => capsule.capsule_id})
             |> json_response(422)
  end

  test "POST /v1/agent/bbh/runs creates a completed BBH run", %{conn: conn} do
    capsule = BBHFixtures.insert_capsule!(%{split: "climb", assignment_policy: "auto_or_select"})
    payload = BBHFixtures.run_submit_payload(capsule, %{normalized_score: 0.83, raw_score: 4.2})

    response =
      conn
      |> with_siwa_headers([])
      |> post("/v1/agent/bbh/runs", payload)
      |> json_response(201)

    assert %{
             "data" => %{
               "run_id" => run_id,
               "status" => "validation_pending",
               "score" => %{"raw" => 4.2, "normalized" => 0.83},
               "validation_state" => "validation_pending",
               "public_run_path" => public_run_path
             }
           } = response

    assert public_run_path == "/bbh/runs/#{run_id}"

    run = Repo.get!(Run, run_id)
    assert run.capsule_id == capsule.capsule_id
    assert run.status == "validation_pending"
    assert run.score_source == "hypotest:hypotest-v1"
    assert get_in(run.run_source, ["solver", "kind"]) == "skydiscover"
    assert get_in(run.run_source, ["search", "summary", "iterations_completed"]) == 6

    assert get_in(run.run_source, ["paths", "search_summary_path"]) ==
             "outputs/skydiscover/search_summary.json"

    assert length(get_in(run.run_source, ["artifact_manifest"]) || []) > 0
    assert get_in(run.run_source, ["evaluator", "dataset_ref"]) == "hypotest://bbh/climb"
  end

  test "benchmark and challenge submissions require an assignment_ref", %{conn: conn} do
    capsule =
      BBHFixtures.insert_capsule!(%{
        split: "benchmark",
        assignment_policy: "select"
      })

    payload = BBHFixtures.run_submit_payload(capsule, %{assignment_ref: nil})

    assert %{"error" => %{"code" => "bbh_assignment_ref_required"}} =
             conn
             |> with_siwa_headers([])
             |> post("/v1/agent/bbh/runs", payload)
             |> json_response(422)
  end

  test "challenge assignments only come from published reviewed capsules", %{conn: conn} do
    _draft_capsule =
      BBHFixtures.insert_capsule!(%{
        split: "draft",
        assignment_policy: "operator",
        provider: "techtree"
      })

    %{capsule: capsule} =
      BBHFixtures.insert_published_challenge_bundle!(%{title: "Fresh Challenge"})

    response =
      conn
      |> with_siwa_headers([])
      |> post("/v1/agent/bbh/assignments/next", %{"split" => "challenge"})
      |> json_response(200)

    assert %{
             "data" => %{
               "split" => "challenge",
               "capsule" => %{"capsule_id" => capsule_id}
             }
           } = response

    assert capsule_id == capsule.capsule_id
  end

  test "POST /v1/agent/bbh/validations stores an official replay validation", %{conn: conn} do
    %{run: run} = BBHFixtures.insert_validated_benchmark_bundle!()
    payload = BBHFixtures.validation_submit_payload(run, %{})

    response =
      conn
      |> with_siwa_headers([])
      |> post("/v1/agent/bbh/validations", payload)
      |> json_response(201)

    assert %{
             "data" => %{
               "validation_id" => validation_id,
               "run_id" => returned_run_id,
               "result" => "confirmed"
             }
           } = response

    assert returned_run_id == run.run_id

    assert %Validation{run_id: ^returned_run_id, result: "confirmed"} =
             Repo.get!(Validation, validation_id)

    assert Repo.get!(Run, run.run_id).status == "validated"

    assert get_in(Repo.get!(Validation, validation_id).review_source, ["bbh", "evaluator_kind"]) ==
             "hypotest"

    assert get_in(Repo.get!(Validation, validation_id).review_source, ["bbh", "score_match"]) ==
             true
  end

  test "POST /v1/agent/bbh/sync returns statuses for submitted runs", %{conn: conn} do
    %{run: run, validation: validation} = BBHFixtures.insert_validated_benchmark_bundle!()

    response =
      conn
      |> with_siwa_headers([])
      |> post("/v1/agent/bbh/sync", %{"run_ids" => [run.run_id]})
      |> json_response(200)

    assert %{
             "data" => %{
               "runs" => [
                 %{
                   "run_id" => run_id,
                   "status" => "validated",
                   "validation_status" => "confirmed"
                 }
               ]
             }
           } = response

    assert run_id == run.run_id
    assert validation.result == "confirmed"
  end

  test "POST /v1/agent/bbh/sync returns the latest validation for multiple runs", %{conn: conn} do
    %{run: first_run} = BBHFixtures.insert_validated_benchmark_bundle!()
    %{run: second_run} = BBHFixtures.insert_validated_benchmark_bundle!()

    BBHFixtures.insert_validation!(first_run, %{
      result: "rejected",
      summary: "A later replay rejected the run."
    })

    response =
      conn
      |> with_siwa_headers([])
      |> post("/v1/agent/bbh/sync", %{"run_ids" => [first_run.run_id, second_run.run_id]})
      |> json_response(200)

    runs_by_id =
      response["data"]["runs"]
      |> Map.new(fn run -> {run["run_id"], run} end)

    assert %{"status" => "validated", "validation_status" => "rejected"} =
             Map.fetch!(runs_by_id, first_run.run_id)

    assert %{"status" => "validated", "validation_status" => "confirmed"} =
             Map.fetch!(runs_by_id, second_run.run_id)
  end

  test "POST /v1/agent/bbh/sync rejects requests that omit run_ids", %{conn: conn} do
    assert %{"error" => %{"code" => "bbh_sync_invalid"}} =
             conn
             |> with_siwa_headers([])
             |> post("/v1/agent/bbh/sync", %{})
             |> json_response(422)
  end

  test "POST /v1/agent/bbh/runs rejects malformed score and status payloads",
       %{conn: conn} do
    capsule = BBHFixtures.insert_capsule!(%{split: "climb", assignment_policy: "auto_or_select"})

    legacy_score_payload =
      capsule
      |> BBHFixtures.run_submit_payload(%{normalized_score: 0.83, raw_score: 4.2})
      |> put_in(["workspace", "verdict_json", "metrics"], %{
        "primary" => 4.2,
        "normalized_score" => 0.83
      })

    assert %{"error" => %{"code" => "bbh_run_invalid", "message" => legacy_score_message}} =
             conn
             |> with_siwa_headers([])
             |> post("/v1/agent/bbh/runs", legacy_score_payload)
             |> json_response(422)

    assert legacy_score_message =~ "workspace.verdict_json.metrics.raw_score is required"

    invalid_status_payload =
      BBHFixtures.run_submit_payload(capsule, %{normalized_score: 0.83, raw_score: 4.2})
      |> put_in(["run_source", "status"], "validation_pending")

    assert %{"error" => %{"code" => "bbh_run_invalid", "message" => status_message}} =
             conn
             |> with_siwa_headers([])
             |> post("/v1/agent/bbh/runs", invalid_status_payload)
             |> json_response(422)

    assert status_message =~ "run_source.status must be one of"

    malformed_status_payload =
      BBHFixtures.run_submit_payload(capsule, %{normalized_score: 0.83, raw_score: 4.2})
      |> put_in(["run_source", "status"], 1)

    assert %{"error" => %{"code" => "bbh_run_invalid", "message" => malformed_status_message}} =
             conn
             |> with_siwa_headers([])
             |> post("/v1/agent/bbh/runs", malformed_status_payload)
             |> json_response(422)

    assert malformed_status_message =~ "run_source.status must be one of"
  end
end
