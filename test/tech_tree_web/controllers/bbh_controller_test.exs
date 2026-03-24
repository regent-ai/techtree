defmodule TechTreeWeb.BbhControllerTest do
  use TechTreeWeb.ConnCase, async: true

  alias TechTree.BBHFixtures

  test "GET /v1/bbh/leaderboard returns official validated benchmark entries", %{conn: conn} do
    %{genome: genome} =
      BBHFixtures.insert_validated_benchmark_bundle!(%{
        label: "Benchmark leader",
        normalized_score: 0.91,
        raw_score: 4.5
      })

    _climb_bundle =
      BBHFixtures.insert_validated_benchmark_bundle!(%{
        label: "Ignored leader",
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

    assert %{
             "name" => "Benchmark leader",
             "score_percent" => 91.0,
             "validated_runs" => 1,
             "harness_type" => "hermes",
             "model_id" => "gpt-test"
           } = leader
  end

  test "GET /v1/bbh/leaderboard can project a validated challenge board", %{conn: conn} do
    %{genome: genome} =
      BBHFixtures.insert_published_challenge_bundle!(%{
        label: "Challenge leader",
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

    assert %{
             "name" => "Challenge leader",
             "score_percent" => 74.0,
             "validated_runs" => 1
           } = leader
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

  test "GET /v1/bbh/genomes/:id, /runs/:id, and /runs/:id/validations return BBH records", %{
    conn: conn
  } do
    %{capsule: capsule, genome: genome, run: run, validation: validation} =
      BBHFixtures.insert_validated_benchmark_bundle!(%{label: "Detail genome"})

    genome_response =
      conn
      |> get("/v1/bbh/genomes/#{genome.genome_id}")
      |> json_response(200)

    assert %{
             "data" => %{
               "genome" => %{
                 "genome_id" => genome_id,
                 "label" => "Detail genome"
               },
               "runs" => [%{"run_id" => run_id}]
             }
           } = genome_response

    assert genome_id == genome.genome_id
    assert run_id == run.run_id

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
