defmodule TechTree.Benchmarks.Domains.BBH do
  @moduledoc false

  import Ecto.Query

  alias TechTree.BBH.{ReviewRequest, ReviewSubmission}

  alias TechTree.Benchmarks.{
    Attempt,
    Capsule,
    Harness,
    CapsuleVersion,
    Validation
  }

  alias TechTree.Repo

  @visible_states [:approved, :published]
  @public_visibility :public
  @known_splits ["climb", "benchmark", "challenge"]
  @review_open_states [:open, :claimed]

  @spec list_capsules(map()) :: [map()]
  def list_capsules(opts \\ %{}) when is_map(opts) do
    opts
    |> capsule_query()
    |> order_by([capsule], asc: capsule.inserted_at, asc: capsule.capsule_id)
    |> Repo.all()
    |> Enum.map(&present_capsule/1)
  end

  @spec list_public_capsules(map()) :: [map()]
  def list_public_capsules(opts \\ %{}) when is_map(opts) do
    opts
    |> capsule_query()
    |> order_by([capsule], asc: capsule.inserted_at, asc: capsule.capsule_id)
    |> Repo.all()
    |> Enum.map(&public_capsule_card/1)
  end

  @spec get_public_capsule(String.t()) :: map() | nil
  def get_public_capsule(capsule_id) when is_binary(capsule_id) do
    capsule_id
    |> fetch_public_capsule()
    |> case do
      nil -> nil
      %Capsule{} = capsule -> public_capsule_detail(capsule)
    end
  end

  @spec list_runs(map()) :: [map()]
  def list_runs(opts \\ %{}) when is_map(opts) do
    split = split_filter(opts)
    validations_query = from validation in Validation, order_by: [desc: validation.inserted_at]

    Attempt
    |> join(:inner, [attempt], capsule in Capsule, on: capsule.capsule_id == attempt.capsule_id)
    |> where([attempt, capsule], capsule.domain == :bbh)
    |> where([attempt, capsule], capsule.visibility == ^@public_visibility)
    |> where([attempt, capsule], capsule.workflow_state in ^@visible_states)
    |> preload([attempt, capsule],
      capsule: capsule,
      harness: [],
      validations: ^validations_query
    )
    |> order_by([attempt], desc: attempt.inserted_at)
    |> Repo.all()
    |> Enum.map(&present_run/1)
    |> filter_runs_by_split(split)
  end

  @spec get_run(String.t()) :: map() | nil
  def get_run(run_id) when is_binary(run_id) do
    case fetch_public_attempt(run_id) do
      nil ->
        nil

      %Attempt{} = attempt ->
        run = present_run(attempt)

        %{
          run: run,
          capsule: run.capsule,
          genome: run.genome,
          validations: run.validations
        }
    end
  end

  @spec get_genome(String.t()) :: map() | nil
  def get_genome(genome_id) when is_binary(genome_id) do
    case fetch_public_harness(genome_id) do
      nil ->
        nil

      %Harness{} = harness ->
        runs =
          Attempt
          |> where([attempt], attempt.harness_id == ^harness.harness_id)
          |> join(:inner, [attempt], capsule in Capsule,
            on: capsule.capsule_id == attempt.capsule_id
          )
          |> where([attempt, capsule], capsule.domain == :bbh)
          |> where([attempt, capsule], capsule.visibility == ^@public_visibility)
          |> where([attempt, capsule], capsule.workflow_state in ^@visible_states)
          |> preload([attempt, capsule], capsule: capsule, harness: [], validations: [])
          |> order_by([attempt], desc: attempt.inserted_at)
          |> limit(20)
          |> Repo.all()
          |> Enum.map(&present_run/1)

        %{genome: present_genome(harness), runs: runs}
    end
  end

  @spec list_validations(String.t()) :: [map()]
  def list_validations(run_id) when is_binary(run_id) do
    case fetch_public_attempt(run_id) do
      nil ->
        []

      %Attempt{} = attempt ->
        Enum.map(attempt.validations || [], &present_validation(&1, attempt))
    end
  end

  @spec leaderboard(map()) :: map()
  def leaderboard(opts \\ %{}) when is_map(opts) do
    split = Map.get(opts, "split") || Map.get(opts, :split) || "benchmark"

    entries =
      opts
      |> Map.put("split", split)
      |> list_runs()
      |> Enum.filter(&officially_confirmed?/1)
      |> Enum.group_by(& &1.genome_id)
      |> Enum.map(fn {_genome_id, runs} ->
        run = Enum.max_by(runs, &(&1.normalized_score || -1.0), fn -> nil end)
        genome = run.genome

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

  @spec certificate_summary(String.t()) :: {:ok, map()} | {:error, :capsule_not_found}
  def certificate_summary(capsule_id) when is_binary(capsule_id) do
    case fetch_public_capsule(capsule_id) do
      nil -> {:error, :capsule_not_found}
      %Capsule{} = capsule -> {:ok, certificate_summary_payload(capsule)}
    end
  end

  @spec review_open_count(String.t()) :: non_neg_integer()
  def review_open_count(capsule_id) when is_binary(capsule_id) do
    legacy_id = legacy_capsule_id_from_any(capsule_id) || capsule_id

    ReviewRequest
    |> where(
      [request],
      request.capsule_id == ^legacy_id and request.visibility == :public_claim and
        request.state in ^@review_open_states
    )
    |> Repo.aggregate(:count, :request_id)
  end

  defp capsule_query(opts) do
    split = split_filter(opts)

    Capsule
    |> where([capsule], capsule.domain == :bbh)
    |> where([capsule], capsule.visibility == ^@public_visibility)
    |> where([capsule], capsule.workflow_state in ^@visible_states)
    |> maybe_filter_capsules_by_split(split)
  end

  defp fetch_public_capsule(id) do
    Capsule
    |> where([capsule], capsule.domain == :bbh)
    |> where([capsule], capsule.visibility == ^@public_visibility)
    |> where([capsule], capsule.workflow_state in ^@visible_states)
    |> where([capsule], capsule.capsule_id == ^id or capsule.legacy_bbh_capsule_id == ^id)
    |> limit(1)
    |> Repo.one()
  end

  defp fetch_public_attempt(id) do
    Attempt
    |> where(
      [attempt],
      attempt.attempt_id == ^id or
        fragment("?->'bbh'->>'legacy_run_id' = ?", attempt.run_source, ^id)
    )
    |> join(:inner, [attempt], capsule in Capsule, on: capsule.capsule_id == attempt.capsule_id)
    |> where([attempt, capsule], capsule.domain == :bbh)
    |> where([attempt, capsule], capsule.visibility == ^@public_visibility)
    |> where([attempt, capsule], capsule.workflow_state in ^@visible_states)
    |> preload([attempt, capsule], capsule: capsule, harness: [], validations: [])
    |> limit(1)
    |> Repo.one()
  end

  defp fetch_public_harness(id) do
    Harness
    |> where(
      [harness],
      harness.harness_id == ^id or
        fragment("?->'bbh'->>'legacy_genome_id' = ?", harness.source, ^id)
    )
    |> limit(1)
    |> Repo.one()
  end

  defp maybe_filter_capsules_by_split(query, nil), do: query

  defp maybe_filter_capsules_by_split(query, split) when is_binary(split) do
    where(query, [capsule], capsule.field == ^split)
  end

  defp maybe_filter_capsules_by_split(query, splits) when is_list(splits) do
    where(query, [capsule], capsule.field in ^splits)
  end

  defp filter_runs_by_split(runs, nil), do: runs

  defp filter_runs_by_split(runs, split) when is_binary(split),
    do: Enum.filter(runs, &(&1.split == split))

  defp filter_runs_by_split(runs, splits) when is_list(splits),
    do: Enum.filter(runs, &(&1.split in splits))

  defp split_filter(opts), do: Map.get(opts, "split") || Map.get(opts, :split)

  defp present_capsule(%Capsule{} = capsule) do
    source = bbh_source(capsule)

    %{
      capsule_id: legacy_capsule_id(capsule),
      benchmark_capsule_id: capsule.capsule_id,
      provider: capsule.provider || source["provider"] || "techtree",
      provider_ref: capsule.provider_ref || source["provider_ref"] || capsule.capsule_id,
      family_ref: capsule.family_ref,
      instance_ref: source["instance_ref"],
      split: bbh_split(capsule),
      language: source["language"] || "python",
      mode: source["mode"] || "fixed",
      assignment_policy: source["assignment_policy"] || "auto_or_select",
      title: capsule.title,
      hypothesis: capsule.summary_md || capsule.question_md,
      protocol_md: capsule.question_md,
      rubric_json: capsule.scoring_policy || %{},
      task_json: source["task_json"] || %{},
      data_files: get_in(source, ["data_manifest", "files"]) || [],
      artifact_source: source["artifact_source"] || %{},
      owner_wallet_address: capsule.owner_wallet_address,
      source_node_id: capsule.source_node_id,
      seed: source["seed"],
      parent_id: source["parent_id"],
      workflow_state: capsule.workflow_state,
      notebook_py: source["notebook_py"],
      capsule_source: current_version_source(capsule),
      recommended_genome_source: source["recommended_genome_source"] || %{},
      genome_notes_md: source["genome_notes_md"],
      publication_artifact_id: source["publication_artifact_id"],
      publication_review_id: source["publication_review_id"],
      published_at: capsule.published_at,
      certificate_status: source["certificate_status"] || "none",
      certificate_review_id: source["certificate_review_id"],
      certificate_scope: source["certificate_scope"],
      certificate_expires_at: source["certificate_expires_at"],
      inserted_at: capsule.inserted_at,
      updated_at: capsule.updated_at
    }
  end

  defp public_capsule_card(%Capsule{} = capsule) do
    presented = present_capsule(capsule)

    %{
      capsule_id: presented.capsule_id,
      split: presented.split,
      title: presented.title,
      hypothesis: presented.hypothesis,
      provider: presented.provider,
      provider_ref: presented.provider_ref,
      assignment_policy: presented.assignment_policy,
      published_at: presented.published_at,
      certificate_status: enum_value(presented.certificate_status || :none),
      certificate_review_id: presented.certificate_review_id,
      certificate_expires_at: presented.certificate_expires_at,
      review_open_count: review_open_count(presented.capsule_id)
    }
  end

  defp public_capsule_detail(%Capsule{} = capsule) do
    presented = present_capsule(capsule)

    Map.merge(public_capsule_card(capsule), %{
      family_ref: presented.family_ref,
      instance_ref: presented.instance_ref,
      language: presented.language,
      mode: presented.mode,
      execution_defaults: execution_defaults(capsule),
      task_summary: presented.task_json,
      rubric_summary: presented.rubric_json,
      data_manifest:
        Enum.map(presented.data_files || [], fn file ->
          Map.take(file, ["name", "path", "sha256", "bytes"])
        end),
      artifact_source: presented.artifact_source,
      review_open?: review_open_count(presented.capsule_id) > 0
    })
  end

  defp present_run(%Attempt{} = attempt) do
    capsule = present_capsule(attempt.capsule)
    genome = present_genome(attempt.harness)

    legacy_run_id =
      get_in(attempt.run_source || %{}, ["bbh", "legacy_run_id"]) || attempt.attempt_id

    split = get_in(attempt.run_source || %{}, ["bbh", "split"]) || capsule.split

    run = %{
      run_id: legacy_run_id,
      benchmark_attempt_id: attempt.attempt_id,
      capsule_id: capsule.capsule_id,
      benchmark_capsule_id: attempt.capsule_id,
      assignment_ref: get_in(attempt.run_source || %{}, ["bbh", "assignment_ref"]),
      genome_id: genome.genome_id,
      canonical_run_id: get_in(attempt.run_source || %{}, ["bbh", "canonical_run_id"]),
      executor_type: get_in(attempt.run_source || %{}, ["executor", "type"]) || "harness",
      harness_type: genome.harness_type,
      harness_version: genome.harness_version,
      split: split,
      status: attempt.status,
      raw_score: attempt.raw_score,
      normalized_score: attempt.normalized_score,
      score_source: attempt.score_source,
      analysis_py: get_in(attempt.workspace_source || %{}, ["analysis_py"]),
      protocol_md: capsule.protocol_md,
      rubric_json: capsule.rubric_json,
      task_json: capsule.task_json,
      verdict_json: attempt.verdict_json || %{},
      final_answer_md: attempt.answer_text,
      report_html: get_in(attempt.workspace_source || %{}, ["report_html"]),
      run_log: get_in(attempt.workspace_source || %{}, ["run_log"]),
      artifact_source: get_in(attempt.run_source || %{}, ["artifact_source"]) || %{},
      genome_source: genome.source || %{},
      run_source: attempt.run_source || %{},
      inserted_at: attempt.inserted_at,
      updated_at: attempt.updated_at,
      validations: Enum.map(attempt.validations || [], &present_validation(&1, attempt)),
      capsule: capsule,
      genome: genome
    }

    Map.put(run, :genome, genome)
  end

  defp present_genome(%Harness{} = harness) do
    bbh = get_in(harness.source || %{}, ["bbh"]) || %{}

    %{
      genome_id: bbh["legacy_genome_id"] || harness.harness_id,
      benchmark_harness_id: harness.harness_id,
      label: harness.name,
      parent_genome_ref: bbh["parent_genome_ref"],
      model_id: harness.model_id,
      harness_type: harness.runner_kind && Atom.to_string(harness.runner_kind),
      harness_version: harness.harness_version,
      prompt_pack_version: get_in(harness.prompt_pack_ref || %{}, ["version"]),
      skill_pack_version: List.first(harness.skill_pack_refs || []) || "benchmark-capsule",
      tool_profile:
        get_in(harness.tool_profile || %{}, ["profile"]) ||
          get_in(harness.tool_profile || %{}, ["tools"]),
      runtime_image: harness.runtime_image,
      helper_code_hash: get_in(harness.dependency_lock_ref || %{}, ["helper_code_hash"]),
      data_profile: bbh["data_profile"],
      axes: bbh["axes"] || %{},
      notes: harness.description_md,
      normalized_bundle_hash: harness.normalized_bundle_hash,
      source: harness.source || %{},
      inserted_at: harness.inserted_at,
      updated_at: harness.updated_at
    }
  end

  defp present_genome(nil) do
    %{
      genome_id: "unknown",
      label: "Unknown harness",
      model_id: nil,
      harness_type: "custom_local",
      harness_version: "unknown",
      tool_profile: nil,
      runtime_image: nil,
      normalized_bundle_hash: nil,
      source: %{}
    }
  end

  defp present_validation(%Validation{} = validation, attempt) do
    %{
      validation_id:
        get_in(validation.review_source || %{}, ["bbh", "legacy_validation_id"]) ||
          validation.validation_id,
      benchmark_validation_id: validation.validation_id,
      run_id: get_in(attempt.run_source || %{}, ["bbh", "legacy_run_id"]) || attempt.attempt_id,
      canonical_review_id:
        get_in(validation.review_source || %{}, ["bbh", "canonical_review_id"]),
      role: validation.role,
      method: validation.method,
      result: validation.result,
      reproduced_raw_score: validation.reproduced_raw_score,
      reproduced_normalized_score: validation.reproduced_normalized_score,
      tolerance_raw_abs: validation.tolerance_raw_abs,
      summary: validation.summary_md,
      review_source: validation.review_source || %{},
      verdict_json: validation.verdict_json || %{},
      report_html: get_in(validation.review_source || %{}, ["bbh", "report_html"]),
      run_log: get_in(validation.review_source || %{}, ["bbh", "run_log"]),
      inserted_at: validation.inserted_at,
      updated_at: validation.updated_at
    }
  end

  defp officially_confirmed?(run) do
    run.status == :validated and
      Enum.any?(run.validations, fn validation ->
        validation.role == :official and validation.method == :replay and
          validation.result == :confirmed
      end)
  end

  defp certificate_summary_payload(%Capsule{} = capsule) do
    source = bbh_source(capsule)
    legacy_id = legacy_capsule_id(capsule)
    review_id = source["certificate_review_id"]

    %{
      capsule_id: legacy_id,
      status: source["certificate_status"] || "none",
      certificate_review_id: review_id,
      scope: source["certificate_scope"],
      issued_at: capsule.updated_at,
      expires_at: source["certificate_expires_at"],
      reviewer_wallet: certificate_reviewer_wallet(review_id)
    }
  end

  defp certificate_reviewer_wallet(nil), do: nil

  defp certificate_reviewer_wallet(review_node_id) do
    case Repo.get_by(ReviewSubmission, review_node_id: review_node_id) do
      nil -> nil
      submission -> submission.reviewer_wallet
    end
  end

  defp execution_defaults(%Capsule{} = capsule) do
    bbh = bbh_source(capsule)

    %{
      "solver" => %{
        "kind" => "skydiscover",
        "entrypoint" => "uv run techtree-bbh sky-search",
        "search_algorithm" => "best_of_n"
      },
      "evaluator" => %{
        "kind" => "hypotest",
        "dataset_ref" => bbh["provider_ref"],
        "benchmark_ref" => legacy_capsule_id(capsule),
        "scorer_version" => "hypotest-v0.1"
      },
      "workspace" => %{
        "analysis_path" => "analysis.py",
        "verdict_path" => "outputs/verdict.json",
        "final_answer_path" => "final_answer.md",
        "report_path" => "outputs/report.html",
        "log_path" => "outputs/run.log",
        "genome_path" => "genome.source.yaml",
        "search_config_path" => "search.config.yaml",
        "evaluator_path" => "eval/hypotest_skydiscover.py",
        "seed_program_path" => "solver/initial_program.py",
        "best_program_path" => "outputs/skydiscover/best_program.py",
        "search_summary_path" => "outputs/skydiscover/search_summary.json",
        "evaluator_artifacts_path" => "outputs/skydiscover/evaluator_artifacts.json",
        "checkpoint_pointer_path" => "outputs/skydiscover/latest_checkpoint.txt",
        "best_solution_patch_path" => "outputs/skydiscover/best_solution.patch",
        "search_log_path" => "outputs/skydiscover/search.log"
      }
    }
  end

  defp legacy_capsule_id(%Capsule{legacy_bbh_capsule_id: value})
       when is_binary(value) and value != "",
       do: value

  defp legacy_capsule_id(%Capsule{} = capsule), do: capsule.capsule_id

  defp legacy_capsule_id_from_any(id) do
    case fetch_public_capsule(id) do
      %Capsule{} = capsule -> legacy_capsule_id(capsule)
      nil -> nil
    end
  end

  defp bbh_split(%Capsule{} = capsule) do
    split = get_in(current_version_source(capsule), ["bbh", "split"]) || capsule.field
    if split in @known_splits, do: split, else: "benchmark"
  end

  defp bbh_source(%Capsule{} = capsule),
    do: get_in(current_version_source(capsule), ["bbh"]) || %{}

  defp current_version_source(%Capsule{} = capsule) do
    CapsuleVersion
    |> where([version], version.capsule_id == ^capsule.capsule_id)
    |> where([version], version.version_id == ^capsule.current_version_id)
    |> limit(1)
    |> Repo.one()
    |> case do
      %CapsuleVersion{} = version -> version.capsule_source || %{}
      nil -> %{}
    end
  end

  defp enum_value(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_value(value), do: value
end
