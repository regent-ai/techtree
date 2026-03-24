defmodule TechTree.BBH do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias TechTree.Repo
  alias TechTree.BBH.{Assignment, Capsule, Genome, Run, Validation}
  alias TechTree.V1.{Artifact, Review}

  @climb_split "climb"
  @benchmark_split "benchmark"
  @challenge_split "challenge"
  @draft_split "draft"
  @public_splits [@climb_split, @benchmark_split, @challenge_split]
  @official_splits [@benchmark_split, @challenge_split]

  def next_assignment(agent_claims, attrs \\ %{}) do
    split = Map.get(attrs, "split", @climb_split)

    with :ok <- ensure_inventory_loaded(),
         true <- split in @public_splits do
      capsule =
        Capsule
        |> where([capsule], capsule.split == ^split)
        |> maybe_limit_to_published_challenges(split)
        |> order_by([capsule], asc: capsule.inserted_at, asc: capsule.capsule_id)
        |> limit(1)
        |> Repo.one()

      case capsule do
        nil ->
          {:error, :assignment_not_available}

        %Capsule{} = capsule ->
          assignment_ref = "asg_" <> Integer.to_string(System.unique_integer([:positive]), 36)

          attrs = %{
            assignment_ref: assignment_ref,
            capsule_id: capsule.capsule_id,
            split: split,
            status: "assigned",
            origin: capsule.assignment_policy,
            agent_wallet_address: Map.get(agent_claims, "wallet_address"),
            agent_token_id: Map.get(agent_claims, "token_id")
          }

          with {:ok, assignment} <- %Assignment{} |> Assignment.changeset(attrs) |> Repo.insert() do
            {:ok,
             %{
               assignment_ref: assignment.assignment_ref,
               split: assignment.split,
               capsule: capsule_payload(capsule)
             }}
          end
      end
    else
      false -> {:error, :invalid_split}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_run(attrs) when is_map(attrs) do
    genome_source = required_map(attrs, "genome_source")
    run_source = required_map(attrs, "run_source")
    workspace = required_map(attrs, "workspace")
    artifact_source = optional_map(attrs, "artifact_source")
    run_id = required_binary(attrs, "run_id")
    capsule_id = required_binary(attrs, "capsule_id")
    assignment_ref = optional_binary(attrs, "assignment_ref")

    with {:ok, capsule} <- fetch_capsule(capsule_id),
         :ok <- validate_assignment_requirement(capsule.split, assignment_ref),
         {:ok, genome_id, genome_changeset} <- genome_changeset(genome_source),
         {:ok, score} <- score_from_workspace(workspace),
         {:ok, run_changeset} <-
           run_changeset(
             run_id,
             capsule,
             genome_id,
             assignment_ref,
             run_source,
             genome_source,
             artifact_source,
             workspace,
             score
           ) do
      Multi.new()
      |> Multi.insert(:genome, genome_changeset,
        on_conflict: {:replace_all_except, [:genome_id, :inserted_at]},
        conflict_target: :genome_id
      )
      |> Multi.insert(:run, run_changeset)
      |> Multi.run(:assignment, fn repo, %{run: run} ->
        maybe_complete_assignment(repo, run.assignment_ref)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{run: run}} ->
          {:ok, %{run: run, genome: Repo.get!(Genome, genome_id)}}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  def create_validation(attrs) when is_map(attrs) do
    review_source = required_map(attrs, "review_source")
    validation_id = required_binary(attrs, "validation_id")
    run_id = required_binary(attrs, "run_id")
    workspace = optional_map(attrs, "workspace") || %{}

    with %Run{} = run <- Repo.get(Run, run_id),
         {:ok, validation_changeset} <-
           validation_changeset(validation_id, run, review_source, workspace) do
      Multi.new()
      |> Multi.insert(:validation, validation_changeset)
      |> Multi.update(:run, Ecto.Changeset.change(run, status: next_run_status(review_source)))
      |> Repo.transaction()
      |> case do
        {:ok, %{validation: validation}} -> {:ok, validation}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      nil -> {:error, :run_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_status(run_ids) when is_list(run_ids) do
    runs =
      Run
      |> where([run], run.run_id in ^run_ids)
      |> Repo.all()

    statuses =
      Enum.map(runs, fn run ->
        latest_validation =
          Validation
          |> where([validation], validation.run_id == ^run.run_id)
          |> order_by([validation], desc: validation.inserted_at)
          |> limit(1)
          |> Repo.one()

        %{
          run_id: run.run_id,
          status: run.status,
          raw_score: run.raw_score,
          normalized_score: run.normalized_score,
          validation_status: latest_validation && latest_validation.result
        }
      end)

    %{runs: statuses}
  end

  def leaderboard(opts \\ %{}) do
    split = Map.get(opts, "split") || Map.get(opts, :split) || @benchmark_split

    runs_query =
      from run in Run,
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
        order_by: [desc: run.normalized_score, desc: run.updated_at]

    entries =
      runs_query
      |> Repo.all()
      |> Enum.group_by(& &1.genome_id)
      |> Enum.map(fn {_genome_id, runs} ->
        run = Enum.max_by(runs, &(&1.normalized_score || -1.0))
        genome = Repo.get!(Genome, run.genome_id)

        %{
          rank: 0,
          run_id: run.run_id,
          genome_id: genome.genome_id,
          name: genome.label || genome.genome_id,
          score_percent: Float.round((run.normalized_score || 0.0) * 100.0, 1),
          final_objective_hit_rate: if((run.raw_score || 0.0) > 0, do: 1.0, else: 0.0),
          validated_runs: length(runs),
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

  def list_runs(opts \\ %{}) do
    split = Map.get(opts, "split") || Map.get(opts, :split)
    validations_query = from validation in Validation, order_by: [desc: validation.inserted_at]

    Run
    |> maybe_filter_runs_by_split(split)
    |> order_by([run], desc: run.inserted_at)
    |> preload([:capsule, :genome, validations: ^validations_query])
    |> Repo.all()
  end

  def list_capsules(opts \\ %{}) do
    split = Map.get(opts, "split") || Map.get(opts, :split)

    Capsule
    |> maybe_filter_capsules_by_split(split)
    |> maybe_limit_capsule_inventory(split)
    |> order_by([capsule], asc: capsule.inserted_at, asc: capsule.capsule_id)
    |> Repo.all()
  end

  def get_run(run_id) when is_binary(run_id) do
    Run
    |> Repo.get(run_id)
    |> case do
      nil ->
        nil

      run ->
        %{
          run: run,
          capsule: Repo.get!(Capsule, run.capsule_id),
          genome: Repo.get!(Genome, run.genome_id),
          validations: list_validations(run.run_id)
        }
    end
  end

  def get_genome(genome_id) when is_binary(genome_id) do
    case Repo.get(Genome, genome_id) do
      nil ->
        nil

      genome ->
        %{
          genome: genome,
          runs:
            Run
            |> where([run], run.genome_id == ^genome_id)
            |> order_by([run], desc: run.inserted_at)
            |> limit(20)
            |> Repo.all()
        }
    end
  end

  def list_validations(run_id) when is_binary(run_id) do
    Validation
    |> where([validation], validation.run_id == ^run_id)
    |> order_by([validation], desc: validation.inserted_at)
    |> Repo.all()
  end

  def upsert_capsule(attrs) when is_map(attrs) do
    capsule_id = required_binary(attrs, "capsule_id")

    %Capsule{}
    |> Capsule.changeset(%{
      capsule_id: capsule_id,
      provider: required_binary(attrs, "provider"),
      provider_ref: required_binary(attrs, "provider_ref"),
      family_ref: optional_binary(attrs, "family_ref"),
      instance_ref: optional_binary(attrs, "instance_ref"),
      split: required_binary(attrs, "split"),
      language: Map.get(attrs, "language", "python"),
      mode: Map.get(attrs, "mode", infer_mode(attrs)),
      assignment_policy: required_binary(attrs, "assignment_policy"),
      title: required_binary(attrs, "title"),
      hypothesis: required_binary(attrs, "hypothesis"),
      protocol_md: required_binary(attrs, "protocol_md"),
      rubric_json: required_map(attrs, "rubric_json"),
      task_json: required_map(attrs, "task_json"),
      data_files: Map.get(attrs, "data_files", []),
      artifact_source: optional_map(attrs, "artifact_source") || %{},
      publication_artifact_id: optional_binary(attrs, "publication_artifact_id"),
      publication_review_id: optional_binary(attrs, "publication_review_id"),
      published_at: fetch_value(attrs, "published_at")
    })
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:capsule_id, :inserted_at]},
      conflict_target: :capsule_id
    )
  end

  defp fetch_capsule(capsule_id) do
    case Repo.get(Capsule, capsule_id) do
      nil -> {:error, :capsule_not_found}
      capsule -> {:ok, capsule}
    end
  end

  defp capsule_payload(capsule) do
    %{
      capsule_id: capsule.capsule_id,
      provider: capsule.provider,
      provider_ref: capsule.provider_ref,
      family_ref: capsule.family_ref,
      instance_ref: capsule.instance_ref,
      split: capsule.split,
      language: capsule.language,
      mode: capsule.mode,
      assignment_policy: capsule.assignment_policy,
      title: capsule.title,
      hypothesis: capsule.hypothesis,
      protocol_md: capsule.protocol_md,
      rubric_json: capsule.rubric_json,
      task_json: capsule.task_json,
      data_files: capsule.data_files,
      artifact_source: capsule.artifact_source,
      publication_artifact_id: capsule.publication_artifact_id,
      publication_review_id: capsule.publication_review_id,
      published_at: capsule.published_at
    }
  end

  defp ensure_inventory_loaded do
    if Repo.aggregate(Capsule, :count, :capsule_id) > 0 do
      :ok
    else
      {:error, :capsule_inventory_empty}
    end
  end

  defp maybe_filter_runs_by_split(query, nil), do: query

  defp maybe_filter_runs_by_split(query, split) when is_binary(split) do
    where(query, [run], run.split == ^split)
  end

  defp maybe_filter_runs_by_split(query, splits) when is_list(splits) do
    where(query, [run], run.split in ^splits)
  end

  defp maybe_filter_capsules_by_split(query, nil), do: query

  defp maybe_filter_capsules_by_split(query, split) when is_binary(split) do
    where(query, [capsule], capsule.split == ^split)
  end

  defp maybe_filter_capsules_by_split(query, splits) when is_list(splits) do
    where(query, [capsule], capsule.split in ^splits)
  end

  defp validate_assignment_requirement(split, assignment_ref)
       when split in @official_splits and (is_nil(assignment_ref) or assignment_ref == ""),
       do: {:error, :assignment_ref_required}

  defp validate_assignment_requirement(_split, _assignment_ref), do: :ok

  defp genome_changeset(source) do
    genome_id = source["genome_id"] || fingerprint_genome(source)

    attrs = %{
      genome_id: genome_id,
      label: source["label"],
      parent_genome_ref: source["parent_genome_ref"],
      model_id: required_binary(source, "model_id"),
      harness_type: required_binary(source, "harness_type"),
      harness_version: required_binary(source, "harness_version"),
      prompt_pack_version: required_binary(source, "prompt_pack_version"),
      skill_pack_version: required_binary(source, "skill_pack_version"),
      tool_profile: required_binary(source, "tool_profile"),
      runtime_image: required_binary(source, "runtime_image"),
      helper_code_hash: source["helper_code_hash"],
      data_profile: source["data_profile"],
      axes: Map.get(source, "axes", %{}),
      notes: source["notes"],
      normalized_bundle_hash:
        :crypto.hash(:sha256, Jason.encode!(normalized_genome_bundle(source)))
        |> Base.encode16(case: :lower),
      source: source
    }

    {:ok, genome_id, Genome.changeset(%Genome{}, attrs)}
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  defp normalized_genome_bundle(source) do
    source
    |> Map.drop(["schema_version", "label", "parent_genome_ref", "notes", "genome_id"])
    |> Enum.sort()
    |> Map.new()
  end

  defp fingerprint_genome(source) do
    "gen_" <>
      (:crypto.hash(:sha256, Jason.encode!(normalized_genome_bundle(source)))
       |> Base.encode16(case: :lower)
       |> binary_part(0, 16))
  end

  defp run_changeset(
         run_id,
         capsule,
         genome_id,
         assignment_ref,
         run_source,
         genome_source,
         artifact_source,
         workspace,
         score
       ) do
    executor = required_map(run_source, "executor")
    status = Map.get(run_source, "status") || "completed"

    attrs = %{
      run_id: run_id,
      capsule_id: capsule.capsule_id,
      assignment_ref: assignment_ref,
      genome_id: genome_id,
      canonical_run_id: Map.get(run_source, "canonical_run_id"),
      executor_type: required_binary(executor, "type"),
      harness_type: required_binary(executor, "harness"),
      harness_version: required_binary(executor, "harness_version"),
      split: required_binary(required_map(run_source, "bbh"), "split"),
      status: normalize_run_status(status, score),
      raw_score: score.raw,
      normalized_score: score.normalized,
      analysis_py: required_binary(workspace, "analysis_py"),
      protocol_md: required_binary(workspace, "protocol_md"),
      rubric_json: required_map(workspace, "rubric_json"),
      task_json: required_map(workspace, "task_json"),
      verdict_json: required_map(workspace, "verdict_json"),
      final_answer_md: optional_binary(workspace, "final_answer_md"),
      report_html: optional_binary(workspace, "report_html"),
      run_log: optional_binary(workspace, "run_log"),
      artifact_source: artifact_source,
      genome_source: genome_source,
      run_source: run_source
    }

    {:ok, Run.changeset(%Run{}, attrs)}
  end

  defp validation_changeset(validation_id, run, review_source, workspace) do
    bbh = required_map(review_source, "bbh")

    attrs = %{
      validation_id: validation_id,
      run_id: run.run_id,
      canonical_review_id: Map.get(review_source, "canonical_review_id"),
      role: required_binary(bbh, "role"),
      method: required_binary(review_source, "method"),
      result: required_binary(review_source, "result"),
      reproduced_raw_score: bbh["reproduced_raw_score"],
      reproduced_normalized_score: bbh["reproduced_normalized_score"],
      tolerance_raw_abs: Map.get(bbh, "raw_abs_tolerance", 0.01),
      summary: required_binary(review_source, "summary"),
      review_source: review_source,
      verdict_json: optional_map(workspace, "verdict_json"),
      report_html: optional_binary(workspace, "report_html"),
      run_log: optional_binary(workspace, "run_log")
    }

    {:ok, Validation.changeset(%Validation{}, attrs)}
  end

  defp maybe_complete_assignment(_repo, nil), do: {:ok, nil}

  defp maybe_complete_assignment(repo, assignment_ref) do
    case repo.get(Assignment, assignment_ref) do
      nil ->
        {:ok, nil}

      assignment ->
        assignment
        |> Ecto.Changeset.change(status: "completed", completed_at: DateTime.utc_now())
        |> repo.update()
    end
  end

  defp next_run_status(review_source) do
    result = required_binary(review_source, "result")
    if result == "confirmed", do: "validated", else: "rejected"
  end

  defp score_from_workspace(workspace) do
    verdict = required_map(workspace, "verdict_json")
    metrics = required_map(verdict, "metrics")

    raw =
      cond do
        is_number(metrics["raw_score"]) -> metrics["raw_score"] * 1.0
        is_number(metrics["primary"]) -> metrics["primary"] * 1.0
        true -> raise ArgumentError, "workspace.verdict_json.metrics.raw_score is required"
      end

    normalized =
      cond do
        is_number(metrics["normalized_score"]) -> metrics["normalized_score"] * 1.0
        true -> raise ArgumentError, "workspace.verdict_json.metrics.normalized_score is required"
      end

    {:ok, %{raw: raw, normalized: normalized}}
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  defp normalize_run_status("completed", _score), do: "validation_pending"
  defp normalize_run_status("failed", _score), do: "failed"
  defp normalize_run_status("running", _score), do: "running"
  defp normalize_run_status(_status, _score), do: "validation_pending"

  defp infer_mode(attrs) do
    if Map.get(attrs, "family_ref") || Map.get(attrs, :family_ref), do: "family", else: "fixed"
  end

  def promote_challenge_capsule(capsule_id, attrs) when is_binary(capsule_id) and is_map(attrs) do
    artifact_id = required_binary(attrs, "publication_artifact_id")
    review_id = required_binary(attrs, "publication_review_id")

    with %Capsule{} = capsule <- Repo.get(Capsule, capsule_id),
         true <- capsule.split == @draft_split || {:error, :capsule_not_draft},
         %Artifact{} <- Repo.get(Artifact, artifact_id) || {:error, :artifact_not_found},
         %Review{} = review <- Repo.get(Review, review_id) || {:error, :review_not_found},
         :ok <- validate_challenge_review(review, artifact_id) do
      capsule
      |> Capsule.changeset(%{
        split: @challenge_split,
        assignment_policy: "operator_assigned",
        publication_artifact_id: artifact_id,
        publication_review_id: review_id,
        published_at: DateTime.utc_now()
      })
      |> Repo.update()
    else
      nil -> {:error, :capsule_not_found}
      false -> {:error, :capsule_not_draft}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  defp validate_challenge_review(
         %Review{
           kind: "challenge",
           target_type: "artifact",
           target_id: artifact_id,
           result: "confirmed"
         },
         artifact_id
       ),
       do: :ok

  defp validate_challenge_review(_review, _artifact_id), do: {:error, :review_not_publishable}

  defp maybe_limit_to_published_challenges(query, @challenge_split) do
    where(query, [capsule], not is_nil(capsule.published_at))
  end

  defp maybe_limit_to_published_challenges(query, _split), do: query

  defp maybe_limit_capsule_inventory(query, @challenge_split) do
    where(query, [capsule], not is_nil(capsule.published_at))
  end

  defp maybe_limit_capsule_inventory(query, splits) when is_list(splits) do
    if @challenge_split in splits do
      where(
        query,
        [capsule],
        capsule.split != ^@challenge_split or not is_nil(capsule.published_at)
      )
    else
      query
    end
  end

  defp maybe_limit_capsule_inventory(query, _split), do: query

  defp required_binary(attrs, key) do
    case fetch_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_binary(attrs, key) do
    case fetch_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp required_map(attrs, key) do
    case fetch_value(attrs, key) do
      value when is_map(value) -> value
      _ -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_map(attrs, key) do
    case fetch_value(attrs, key) do
      value when is_map(value) -> value
      _ -> nil
    end
  end

  defp fetch_value(attrs, key) when is_map(attrs) and is_binary(key) do
    try do
      case Map.fetch(attrs, key) do
        {:ok, value} ->
          value

        :error ->
          atom_key = String.to_existing_atom(key)
          Map.get(attrs, atom_key)
      end
    rescue
      ArgumentError -> nil
    end
  end
end
