defmodule TechTreeWeb.BbhControllerTest do
  use TechTreeWeb.ConnCase, async: false

  alias TechTree.BBHFixtures

  test "GET /v1/bbh/leaderboard returns official validated benchmark entries", %{conn: conn} do
    %{genome: genome} =
      BBHFixtures.insert_validated_benchmark_bundle!(%{
        normalized_score: 0.91,
        raw_score: 4.5
      })

    _climb_bundle =
      BBHFixtures.insert_validated_benchmark_bundle!(%{
        model_id: "gpt-train",
        normalized_score: 0.99,
        raw_score: 5.0,
        split: "climb"
      })

    response =
      conn
      |> get("/v1/bbh/leaderboard")
      |> json_response(200)

    assert response["data"]["benchmark"] == "bbh_py"
    assert response["data"]["split"] == "benchmark"

    leader =
      Enum.find(response["data"]["entries"], fn entry ->
        entry["genome_id"] == genome.genome_id
      end)

    assert leader["name"] == genome.label
    assert leader["score_percent"] == 91.0
    assert leader["validated_runs"] == 1
    assert leader["harness_type"] == "hermes"
    assert leader["model_id"] == "gpt-test"
  end

  test "GET /v1/bbh/leaderboard can project a validated challenge board", %{conn: conn} do
    %{genome: genome} =
      BBHFixtures.insert_published_challenge_bundle!(%{
        normalized_score: 0.74,
        raw_score: 3.8
      })

    response =
      conn
      |> get("/v1/bbh/leaderboard", %{"split" => "challenge"})
      |> json_response(200)

    assert response["data"]["split"] == "challenge"

    leader =
      Enum.find(response["data"]["entries"], fn entry ->
        entry["genome_id"] == genome.genome_id
      end)

    assert leader["name"] == genome.label
    assert leader["score_percent"] == 74.0
    assert leader["validated_runs"] == 1
  end

  test "GET /v1/bbh/capsules returns narrow public inventory and hides drafts", %{conn: conn} do
    draft_capsule =
      BBHFixtures.insert_capsule!(%{
        split: "draft",
        assignment_policy: "operator",
        provider: "techtree",
        title: "Hidden Draft"
      })

    %{capsule: public_capsule} =
      BBHFixtures.insert_published_challenge_capsule!(%{
        title: "Public Challenge",
        assignment_policy: "auto_or_select"
      })

    response =
      conn
      |> get("/v1/bbh/capsules")
      |> json_response(200)

    assert Enum.any?(response["data"], &(&1["capsule_id"] == public_capsule.capsule_id))
    refute Enum.any?(response["data"], &(&1["capsule_id"] == draft_capsule.capsule_id))

    public_entry = Enum.find(response["data"], &(&1["capsule_id"] == public_capsule.capsule_id))

    assert public_entry["title"] == "Public Challenge"
    refute Map.has_key?(public_entry, "protocol_md")
    refute Map.has_key?(public_entry, "task_summary")
  end

  test "GET /v1/bbh/capsules/:id returns browse detail for public capsules and hides drafts",
       %{conn: conn} do
    draft_capsule =
      BBHFixtures.insert_capsule!(%{
        split: "draft",
        assignment_policy: "operator",
        provider: "techtree",
        title: "Hidden Draft"
      })

    %{capsule: public_capsule} =
      BBHFixtures.insert_published_challenge_capsule!(%{
        title: "Public Challenge",
        assignment_policy: "auto_or_select"
      })

    response =
      conn
      |> get("/v1/bbh/capsules/#{public_capsule.capsule_id}")
      |> json_response(200)

    assert %{
             "data" => %{
               "capsule_id" => capsule_id,
               "title" => "Public Challenge",
               "task_summary" => task_summary,
               "rubric_summary" => rubric_summary,
               "execution_defaults" => %{
                 "solver" => %{"kind" => "skydiscover"},
                 "workspace" => %{
                   "search_summary_path" => "outputs/skydiscover/search_summary.json"
                 }
               }
             }
           } = response

    assert capsule_id == public_capsule.capsule_id
    assert task_summary == public_capsule.task_json
    assert rubric_summary == public_capsule.rubric_json
    refute Map.has_key?(response["data"], "protocol_md")

    assert %{"error" => %{"code" => "bbh_capsule_not_found"}} =
             conn
             |> get("/v1/bbh/capsules/#{draft_capsule.capsule_id}")
             |> json_response(404)
  end

  test "GET /v1/bbh/leaderboard?split=challenge ignores seeded capsules without validated runs",
       %{conn: conn} do
    BBHFixtures.insert_published_challenge_capsule!(%{
      title: "Seeded Frontier Capsule"
    })

    response =
      conn
      |> get("/v1/bbh/leaderboard", %{"split" => "challenge"})
      |> json_response(200)

    assert response["data"]["split"] == "challenge"
    assert response["data"]["entries"] == []
  end

  test "GET /v1/bbh/capsules/:id/certificate returns certificate summary for public capsules", %{
    conn: conn
  } do
    %{capsule: capsule} =
      BBHFixtures.insert_published_challenge_capsule!(%{
        title: "Certified Challenge"
      })

    BBHFixtures.certify_capsule!(capsule)

    response =
      conn
      |> get("/v1/bbh/capsules/#{capsule.capsule_id}/certificate")
      |> json_response(200)

    assert get_in(response, ["data", "status"]) == "active"
    assert get_in(response, ["data", "certificate_review_id"]) =~ "0xreview"
  end

  test "GET /v1/bbh/genomes/:id, /runs/:id, and /runs/:id/validations return BBH records", %{
    conn: conn
  } do
    %{capsule: capsule, genome: genome, run: run, validation: validation} =
      BBHFixtures.insert_validated_benchmark_bundle!()

    genome_response =
      conn
      |> get("/v1/bbh/genomes/#{genome.genome_id}")
      |> json_response(200)

    assert %{
             "data" => %{
               "genome" => %{
                 "genome_id" => genome_id,
                 "label" => label
               }
             }
           } = genome_response

    assert genome_id == genome.genome_id
    assert label == genome.label
    assert Enum.any?(genome_response["data"]["runs"], &(&1["run_id"] == run.run_id))

    run_response =
      conn
      |> get("/v1/bbh/runs/#{run.run_id}")
      |> json_response(200)

    assert %{
             "data" => %{
               "run" => %{"run_id" => returned_run_id, "status" => "validated"},
               "capsule" => %{"capsule_id" => returned_capsule_id},
               "genome" => %{"genome_id" => returned_genome_id},
               "validations" => [%{"validation_id" => returned_validation_id}]
             }
           } = run_response

    assert returned_run_id == run.run_id
    assert returned_capsule_id == capsule.capsule_id
    assert returned_genome_id == genome.genome_id
    assert returned_validation_id == validation.validation_id

    validations_response =
      conn
      |> get("/v1/bbh/runs/#{run.run_id}/validations")
      |> json_response(200)

    assert %{
             "data" => [
               %{
                 "validation_id" => validation_id,
                 "run_id" => run_id,
                 "role" => "official",
                 "method" => "replay",
                 "result" => "confirmed"
               }
             ]
           } = validations_response

    assert validation_id == validation.validation_id
    assert run_id == run.run_id
  end

  test "GET /v1/bbh routes return not found for missing records", %{conn: conn} do
    assert %{"error" => %{"code" => "bbh_genome_not_found"}} =
             conn
             |> get("/v1/bbh/genomes/missing")
             |> json_response(404)

    assert %{"error" => %{"code" => "bbh_run_not_found"}} =
             conn
             |> get("/v1/bbh/runs/missing")
             |> json_response(404)
  end
end
