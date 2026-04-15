defmodule TechTree.BBH.RunReads do
  @moduledoc false

  import Ecto.Query

  alias TechTree.BBH.{Capsule, Genome, Run, Validation}
  alias TechTree.Repo

  @benchmark_split "benchmark"

  def sync_status(run_ids) when is_list(run_ids) do
    unique_run_ids = Enum.uniq(run_ids)

    runs_by_id =
      Run
      |> where([run], run.run_id in ^unique_run_ids)
      |> Repo.all()
      |> Map.new(&{&1.run_id, &1})

    latest_validations_by_run_id =
      Validation
      |> where([validation], validation.run_id in ^unique_run_ids)
      |> select([validation], %{
        run_id: validation.run_id,
        result: validation.result,
        rank:
          over(
            row_number(),
            :latest_validation_per_run
          )
      })
      |> windows(
        [validation],
        latest_validation_per_run: [
          partition_by: validation.run_id,
          order_by: [desc: validation.inserted_at, desc: validation.updated_at]
        ]
      )
      |> subquery()
      |> where([validation], validation.rank == 1)
      |> Repo.all()
      |> Map.new(&{&1.run_id, &1})

    statuses =
      unique_run_ids
      |> Enum.flat_map(fn run_id ->
        case Map.fetch(runs_by_id, run_id) do
          {:ok, run} ->
            latest_validation = Map.get(latest_validations_by_run_id, run_id)

            [
              %{
                run_id: run.run_id,
                status: run.status,
                raw_score: run.raw_score,
                normalized_score: run.normalized_score,
                validation_status: latest_validation && latest_validation.result
              }
            ]

          :error ->
            []
        end
      end)

    %{runs: statuses}
  end

  def leaderboard(opts \\ %{}) do
    split = Map.get(opts, "split") || Map.get(opts, :split) || @benchmark_split

    run_rows =
      from(run in Run,
        join: validation in Validation,
        on: validation.run_id == run.run_id,
        join: genome in Genome,
        on: genome.genome_id == run.genome_id,
        join: capsule in Capsule,
        on: capsule.capsule_id == run.capsule_id,
        where:
          run.split == ^split and
            run.status == "validated" and
            validation.role == "official" and
            validation.method == "replay" and
            validation.result == "confirmed",
        distinct: run.run_id,
        order_by: [asc: run.run_id, desc: run.normalized_score, desc: run.updated_at],
        select: %{run: run, genome: genome}
      )
      |> Repo.all()

    entries =
      run_rows
      |> Enum.group_by(& &1.run.genome_id)
      |> Enum.map(fn {_genome_id, grouped_rows} ->
        %{run: run, genome: genome} =
          Enum.max_by(grouped_rows, &(&1.run.normalized_score || -1.0), fn -> nil end)

        %{
          rank: 0,
          run_id: run.run_id,
          genome_id: genome.genome_id,
          name: genome.label || genome.genome_id,
          score_percent: Float.round((run.normalized_score || 0.0) * 100.0, 1),
          final_objective_hit_rate: if((run.raw_score || 0.0) > 0, do: 1.0, else: 0.0),
          validated_runs: length(grouped_rows),
          reproducibility_rate: 1.0,
          median_latency_sec: nil,
          median_cost_usd: nil,
          harness_type: genome.harness_type,
          model_id: genome.model_id,
          updated_at: run.updated_at
        }
      end)
      |> Enum.sort_by(fn entry -> {-entry.score_percent, -entry.validated_runs, entry.name} end)
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, index} -> %{entry | rank: index} end)

    %{
      benchmark: "bbh_py",
      split: split,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      entries: entries
    }
  end
end
