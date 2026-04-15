defmodule TechTree.BBH.RunIngest do
  @moduledoc false

  alias Ecto.Multi
  alias TechTree.BBH.{Assignment, Genome, Helpers, Run, Validation}
  alias TechTree.Repo

  @official_splits ["benchmark", "challenge"]

  def create_run(attrs) when is_map(attrs) do
    genome_source = Helpers.required_map(attrs, "genome_source")
    run_source = Helpers.required_map(attrs, "run_source")
    workspace = Helpers.required_map(attrs, "workspace")
    artifact_source = Helpers.optional_map(attrs, "artifact_source")
    run_id = Helpers.required_binary(attrs, "run_id")
    capsule_id = Helpers.required_binary(attrs, "capsule_id")
    assignment_ref = Helpers.optional_binary(attrs, "assignment_ref")

    with {:ok, capsule} <- Helpers.fetch_capsule(capsule_id),
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
    review_source = Helpers.required_map(attrs, "review_source")
    validation_id = Helpers.required_binary(attrs, "validation_id")
    run_id = Helpers.required_binary(attrs, "run_id")
    workspace = Helpers.optional_map(attrs, "workspace") || %{}

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
      model_id: Helpers.required_binary(source, "model_id"),
      harness_type: Helpers.required_binary(source, "harness_type"),
      harness_version: Helpers.required_binary(source, "harness_version"),
      prompt_pack_version: Helpers.required_binary(source, "prompt_pack_version"),
      skill_pack_version: Helpers.required_binary(source, "skill_pack_version"),
      tool_profile: Helpers.required_binary(source, "tool_profile"),
      runtime_image: Helpers.required_binary(source, "runtime_image"),
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
    executor = Helpers.required_map(run_source, "executor")
    status = Map.get(run_source, "status") || "completed"

    attrs = %{
      run_id: run_id,
      capsule_id: capsule.capsule_id,
      assignment_ref: assignment_ref,
      genome_id: genome_id,
      canonical_run_id: Map.get(run_source, "canonical_run_id"),
      executor_type: Helpers.required_binary(executor, "type"),
      harness_type: Helpers.required_binary(executor, "harness"),
      harness_version: Helpers.required_binary(executor, "harness_version"),
      split: Helpers.required_binary(Helpers.required_map(run_source, "bbh"), "split"),
      status: normalize_run_status(status, score),
      raw_score: score.raw,
      normalized_score: score.normalized,
      analysis_py: Helpers.required_binary(workspace, "analysis_py"),
      protocol_md: Helpers.required_binary(workspace, "protocol_md"),
      rubric_json: Helpers.required_map(workspace, "rubric_json"),
      task_json: Helpers.required_map(workspace, "task_json"),
      verdict_json: Helpers.required_map(workspace, "verdict_json"),
      final_answer_md: Helpers.optional_binary(workspace, "final_answer_md"),
      report_html: Helpers.optional_binary(workspace, "report_html"),
      run_log: Helpers.optional_binary(workspace, "run_log"),
      artifact_source: artifact_source,
      genome_source: genome_source,
      run_source: run_source
    }

    {:ok, Run.changeset(%Run{}, attrs)}
  end

  defp validation_changeset(validation_id, run, review_source, workspace) do
    bbh = Helpers.required_map(review_source, "bbh")

    attrs = %{
      validation_id: validation_id,
      run_id: run.run_id,
      canonical_review_id: Map.get(review_source, "canonical_review_id"),
      role: Helpers.required_binary(bbh, "role"),
      method: Helpers.required_binary(review_source, "method"),
      result: Helpers.required_binary(review_source, "result"),
      reproduced_raw_score: bbh["reproduced_raw_score"],
      reproduced_normalized_score: bbh["reproduced_normalized_score"],
      tolerance_raw_abs: Map.get(bbh, "raw_abs_tolerance", 0.01),
      summary: Helpers.required_binary(review_source, "summary"),
      review_source: review_source,
      verdict_json: Helpers.optional_map(workspace, "verdict_json"),
      report_html: Helpers.optional_binary(workspace, "report_html"),
      run_log: Helpers.optional_binary(workspace, "run_log")
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
    result = Helpers.required_binary(review_source, "result")
    if result == "confirmed", do: "validated", else: "rejected"
  end

  defp score_from_workspace(workspace) do
    verdict = Helpers.required_map(workspace, "verdict_json")
    metrics = Helpers.required_map(verdict, "metrics")

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
end
