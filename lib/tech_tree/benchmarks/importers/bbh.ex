defmodule TechTree.Benchmarks.Importers.BBH do
  @moduledoc false

  alias TechTree.BBH.{Capsule, Genome, ReviewSubmission, Run, Validation}

  alias TechTree.Benchmarks.{Artifact, Attempt, CapsuleVersion, Harness, Reliability}

  alias TechTree.Repo

  @public_splits ["climb", "benchmark", "challenge"]

  @spec backfill_all(keyword()) :: {:ok, map()} | {:error, term()}
  def backfill_all(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)

    with {:ok, capsules} <- backfill_capsules(dry_run?),
         {:ok, harnesses} <- backfill_harnesses(dry_run?),
         {:ok, attempts} <- backfill_attempts(dry_run?),
         {:ok, validations} <- backfill_validations(dry_run?) do
      {:ok,
       %{
         capsules: capsules,
         harnesses: harnesses,
         attempts: attempts,
         validations: validations
       }}
    end
  end

  @spec upsert_capsule(Capsule.t()) :: {:ok, TechTree.Benchmarks.Capsule.t()} | {:error, term()}
  def upsert_capsule(%Capsule{} = capsule) do
    version_id = version_id(capsule.capsule_id)
    benchmark_capsule_id = capsule_id(capsule.capsule_id)

    Repo.transaction(fn ->
      with {:ok, benchmark_capsule} <-
             upsert_benchmark_capsule(capsule, benchmark_capsule_id, version_id),
           {:ok, _version} <- upsert_version(capsule, benchmark_capsule_id, version_id),
           {:ok, _artifact} <-
             upsert_data_manifest_artifact(capsule, benchmark_capsule_id, version_id) do
        benchmark_capsule
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec upsert_harness(Genome.t()) :: {:ok, Harness.t()} | {:error, term()}
  def upsert_harness(%Genome{} = genome) do
    attrs = harness_attrs(genome)

    %Harness{}
    |> Harness.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :name,
           :description_md,
           :domain,
           :runner_kind,
           :model_id,
           :agent_runtime,
           :harness_version,
           :prompt_pack_ref,
           :skill_pack_refs,
           :tool_profile,
           :runtime_image,
           :dependency_lock_ref,
           :workspace_policy,
           :source,
           :updated_at
         ]},
      conflict_target: :harness_id,
      returning: true
    )
  end

  @spec upsert_run(Run.t()) :: {:ok, Attempt.t()} | {:error, term()}
  def upsert_run(%Run{} = run) do
    run = Repo.preload(run, [:capsule, :genome, :validations])

    with %Capsule{} = capsule <- run.capsule || Repo.get(Capsule, run.capsule_id),
         %Genome{} = genome <- run.genome || Repo.get(Genome, run.genome_id),
         {:ok, _capsule} <- upsert_capsule(capsule),
         {:ok, harness} <- upsert_harness(genome) do
      attrs = attempt_attrs(run, capsule, harness)

      result =
        %Attempt{}
        |> Attempt.changeset(attrs)
        |> Repo.insert(
          on_conflict:
            {:replace,
             [
               :capsule_id,
               :version_id,
               :harness_id,
               :solver_wallet_address,
               :repeat_group_id,
               :attempt_ordinal,
               :status,
               :score_status,
               :raw_score,
               :normalized_score,
               :score_source,
               :solved,
               :answer_text,
               :answer_hash,
               :verdict_json,
               :artifact_manifest,
               :run_source,
               :workspace_source,
               :submitted_at,
               :validated_at,
               :updated_at
             ]},
          conflict_target: :attempt_id,
          returning: true
        )

      with {:ok, attempt} <- result do
        Enum.reduce_while(run.validations || [], {:ok, attempt}, fn validation, {:ok, _attempt} ->
          case upsert_validation(validation) do
            {:ok, _validation} -> {:cont, {:ok, attempt}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, attempt} ->
            _ =
              Reliability.recompute_group(
                attempt.capsule_id,
                attempt.version_id,
                attempt.harness_id,
                attempt.repeat_group_id
              )

            {:ok, attempt}

          {:error, reason} ->
            {:error, reason}
        end
      end
    else
      nil -> {:error, :bbh_run_missing_source}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec upsert_validation(Validation.t()) ::
          {:ok, TechTree.Benchmarks.Validation.t()} | {:error, term()}
  def upsert_validation(%Validation{} = validation) do
    validation = Repo.preload(validation, run: [:capsule, :genome])
    run = validation.run || Repo.get(Run, validation.run_id)

    with %Run{} <- run,
         {:ok, attempt} <- upsert_run_without_validations(run) do
      attrs = validation_attrs(validation, attempt)

      %TechTree.Benchmarks.Validation{}
      |> TechTree.Benchmarks.Validation.changeset(attrs)
      |> Repo.insert(
        on_conflict:
          {:replace,
           [
             :attempt_id,
             :capsule_id,
             :role,
             :method,
             :result,
             :reproduced_raw_score,
             :reproduced_normalized_score,
             :tolerance_raw_abs,
             :summary_md,
             :verdict_json,
             :review_source,
             :updated_at
           ]},
        conflict_target: :validation_id,
        returning: true
      )
      |> case do
        {:ok, imported} ->
          _ =
            Reliability.recompute_group(
              attempt.capsule_id,
              attempt.version_id,
              attempt.harness_id,
              attempt.repeat_group_id
            )

          {:ok, imported}

        {:error, reason} ->
          {:error, reason}
      end
    else
      nil -> {:error, :bbh_validation_missing_run}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec upsert_review_submission(ReviewSubmission.t()) ::
          {:ok, TechTree.Benchmarks.Validation.t()} | {:error, term()}
  def upsert_review_submission(%ReviewSubmission{} = submission) do
    with %Capsule{} = capsule <- Repo.get(Capsule, submission.capsule_id),
         {:ok, _benchmark_capsule} <- upsert_capsule(capsule),
         {:ok, harness} <- upsert_review_harness(),
         {:ok, attempt} <- upsert_review_attempt(submission, capsule, harness) do
      attrs = review_validation_attrs(submission, attempt)

      %TechTree.Benchmarks.Validation{}
      |> TechTree.Benchmarks.Validation.changeset(attrs)
      |> Repo.insert(
        on_conflict:
          {:replace,
           [
             :attempt_id,
             :capsule_id,
             :validator_wallet_address,
             :role,
             :method,
             :result,
             :summary_md,
             :verdict_json,
             :review_source,
             :updated_at
           ]},
        conflict_target: :validation_id,
        returning: true
      )
      |> case do
        {:ok, imported} ->
          _ =
            Reliability.recompute_group(
              attempt.capsule_id,
              attempt.version_id,
              attempt.harness_id,
              attempt.repeat_group_id
            )

          {:ok, imported}

        {:error, reason} ->
          {:error, reason}
      end
    else
      nil -> {:error, :bbh_review_submission_missing_capsule}
      {:error, reason} -> {:error, reason}
    end
  end

  defp upsert_run_without_validations(%Run{} = run) do
    run = Repo.preload(run, [:capsule, :genome])

    with %Capsule{} = capsule <- run.capsule || Repo.get(Capsule, run.capsule_id),
         %Genome{} = genome <- run.genome || Repo.get(Genome, run.genome_id),
         {:ok, _capsule} <- upsert_capsule(capsule),
         {:ok, harness} <- upsert_harness(genome) do
      attrs = attempt_attrs(run, capsule, harness)

      %Attempt{}
      |> Attempt.changeset(attrs)
      |> Repo.insert(
        on_conflict:
          {:replace,
           [
             :capsule_id,
             :version_id,
             :harness_id,
             :solver_wallet_address,
             :repeat_group_id,
             :attempt_ordinal,
             :status,
             :score_status,
             :raw_score,
             :normalized_score,
             :score_source,
             :solved,
             :answer_text,
             :answer_hash,
             :verdict_json,
             :artifact_manifest,
             :run_source,
             :workspace_source,
             :submitted_at,
             :validated_at,
             :updated_at
           ]},
        conflict_target: :attempt_id,
        returning: true
      )
    else
      nil -> {:error, :bbh_run_missing_source}
      {:error, reason} -> {:error, reason}
    end
  end

  defp upsert_review_harness do
    attrs = %{
      "harness_id" => review_harness_id(),
      "name" => "BBH certificate review",
      "description_md" => "Human certificate review for BBH capsules.",
      "domain" => "bbh",
      "runner_kind" => "manual_human",
      "harness_version" => "review-v1",
      "prompt_pack_ref" => %{},
      "skill_pack_refs" => [],
      "tool_profile" => %{"review" => "certificate"},
      "dependency_lock_ref" => %{},
      "workspace_policy" => %{"mode" => "review"},
      "normalized_bundle_hash" => hash_term(%{"bbh_review_harness" => "v1"}),
      "source" => %{"bbh" => %{"kind" => "certificate_review"}}
    }

    %Harness{}
    |> Harness.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :name,
           :description_md,
           :domain,
           :runner_kind,
           :harness_version,
           :tool_profile,
           :workspace_policy,
           :source,
           :updated_at
         ]},
      conflict_target: :harness_id,
      returning: true
    )
  end

  defp upsert_review_attempt(submission, capsule, harness) do
    attrs = review_attempt_attrs(submission, capsule, harness)

    %Attempt{}
    |> Attempt.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :capsule_id,
           :version_id,
           :harness_id,
           :solver_wallet_address,
           :repeat_group_id,
           :attempt_ordinal,
           :status,
           :score_status,
           :solved,
           :answer_text,
           :answer_hash,
           :verdict_json,
           :artifact_manifest,
           :run_source,
           :workspace_source,
           :submitted_at,
           :validated_at,
           :updated_at
         ]},
      conflict_target: :attempt_id,
      returning: true
    )
  end

  defp backfill_capsules(dry_run?) do
    Capsule
    |> Repo.all()
    |> upsert_many(dry_run?, &upsert_capsule/1)
  end

  defp backfill_harnesses(dry_run?) do
    Genome
    |> Repo.all()
    |> upsert_many(dry_run?, &upsert_harness/1)
  end

  defp backfill_attempts(dry_run?) do
    Run
    |> Repo.all()
    |> upsert_many(dry_run?, &upsert_run/1)
  end

  defp backfill_validations(dry_run?) do
    Validation
    |> Repo.all()
    |> upsert_many(dry_run?, &upsert_validation/1)
  end

  defp upsert_many(records, true, _fun), do: {:ok, length(records)}

  defp upsert_many(records, false, fun) do
    Enum.reduce_while(records, {:ok, 0}, fn record, {:ok, count} ->
      case fun.(record) do
        {:ok, _result} -> {:cont, {:ok, count + 1}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp upsert_benchmark_capsule(capsule, benchmark_capsule_id, version_id) do
    attrs = capsule_attrs(capsule, benchmark_capsule_id, version_id)

    %TechTree.Benchmarks.Capsule{}
    |> TechTree.Benchmarks.Capsule.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :legacy_bbh_capsule_id,
           :source_node_id,
           :owner_wallet_address,
           :domain,
           :field,
           :family_ref,
           :provider,
           :provider_ref,
           :title,
           :summary_md,
           :question_md,
           :difficulty_label,
           :human_baseline_status,
           :ground_truth_policy,
           :answer_format,
           :allowed_tools_policy,
           :external_resource_policy,
           :scoring_policy,
           :anti_cheat_policy,
           :workflow_state,
           :visibility,
           :current_version_id,
           :published_at,
           :updated_at
         ]},
      conflict_target: :capsule_id,
      returning: true
    )
  end

  defp upsert_version(capsule, benchmark_capsule_id, version_id) do
    attrs = version_attrs(capsule, benchmark_capsule_id, version_id)

    %CapsuleVersion{}
    |> CapsuleVersion.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :version_label,
           :version_status,
           :manifest_sha256,
           :input_bundle_sha256,
           :ground_truth_storage_policy,
           :environment_lock_ref,
           :data_manifest,
           :capsule_source,
           :updated_at
         ]},
      conflict_target: :version_id,
      returning: true
    )
  end

  defp upsert_data_manifest_artifact(capsule, benchmark_capsule_id, version_id) do
    attrs = %{
      "artifact_id" => stable_id("artifact_bbh_data", capsule.capsule_id),
      "capsule_id" => benchmark_capsule_id,
      "version_id" => version_id,
      "kind" => "data_manifest",
      "name" => "#{capsule.title} data manifest",
      "sha256" => hash_term(capsule.data_files || []),
      "storage_provider" => "techtree",
      "visibility" => if(public_capsule?(capsule), do: "public", else: "private"),
      "encryption_meta" => %{},
      "license" => get_in(capsule.artifact_source || %{}, ["license"])
    }

    %Artifact{}
    |> Artifact.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:name, :sha256, :storage_provider, :visibility, :encryption_meta, :license, :updated_at]},
      conflict_target: :artifact_id,
      returning: true
    )
  end

  defp capsule_attrs(capsule, benchmark_capsule_id, version_id) do
    %{
      "capsule_id" => benchmark_capsule_id,
      "legacy_bbh_capsule_id" => capsule.capsule_id,
      "source_node_id" => capsule.source_node_id,
      "owner_wallet_address" => capsule.owner_wallet_address,
      "domain" => "bbh",
      "field" => capsule.split,
      "family_ref" => capsule.family_ref,
      "provider" => capsule.provider,
      "provider_ref" => capsule.provider_ref,
      "title" => capsule.title,
      "summary_md" => capsule.hypothesis,
      "question_md" => capsule.protocol_md || capsule.hypothesis || capsule.title,
      "difficulty_label" => get_in(capsule.task_json || %{}, ["difficulty"]) || capsule.split,
      "human_baseline_status" => "unknown",
      "ground_truth_policy" => "hidden_server",
      "answer_format" => %{"type" => "notebook_verdict"},
      "allowed_tools_policy" => %{"lane" => capsule.split},
      "external_resource_policy" => %{"allowed" => true},
      "scoring_policy" => capsule.rubric_json || %{},
      "anti_cheat_policy" => %{"notes" => "Hidden answers are not published."},
      "workflow_state" => benchmark_workflow_state(capsule),
      "visibility" => benchmark_visibility(capsule),
      "current_version_id" => version_id,
      "published_at" => capsule.published_at || capsule.updated_at
    }
  end

  defp version_attrs(capsule, benchmark_capsule_id, version_id) do
    source = bbh_capsule_source(capsule)

    %{
      "version_id" => version_id,
      "capsule_id" => benchmark_capsule_id,
      "version_label" => "v1",
      "version_status" => benchmark_version_status(capsule),
      "manifest_sha256" => hash_term(source),
      "input_bundle_sha256" => hash_term(capsule.data_files || []),
      "ground_truth_storage_policy" => %{"policy" => "hidden_server"},
      "environment_lock_ref" => %{"language" => capsule.language || "python"},
      "data_manifest" => %{"files" => capsule.data_files || []},
      "capsule_source" => %{"bbh" => source}
    }
  end

  defp harness_attrs(%Genome{} = genome) do
    %{
      "harness_id" => harness_id(genome.genome_id),
      "name" => genome.label || genome.genome_id,
      "description_md" => genome.notes,
      "domain" => "bbh",
      "runner_kind" => runner_kind(genome.harness_type),
      "model_id" => genome.model_id,
      "agent_runtime" => genome.harness_type,
      "harness_version" => genome.harness_version,
      "prompt_pack_ref" => %{"version" => genome.prompt_pack_version},
      "skill_pack_refs" => [%{"version" => genome.skill_pack_version}],
      "tool_profile" => %{"profile" => genome.tool_profile},
      "runtime_image" => genome.runtime_image,
      "dependency_lock_ref" => %{"helper_code_hash" => genome.helper_code_hash},
      "workspace_policy" => %{"data_profile" => genome.data_profile},
      "normalized_bundle_hash" =>
        genome.normalized_bundle_hash || hash_term(genome.source || %{}),
      "source" => %{
        "bbh" => %{
          "legacy_genome_id" => genome.genome_id,
          "parent_genome_ref" => genome.parent_genome_ref,
          "data_profile" => genome.data_profile,
          "axes" => genome.axes || %{}
        },
        "legacy_source" => genome.source || %{}
      }
    }
  end

  defp attempt_attrs(%Run{} = run, %Capsule{} = capsule, %Harness{} = harness) do
    version = version_id(capsule.capsule_id)
    run_source = run.run_source || %{}

    workspace_source = %{
      "analysis_py" => run.analysis_py,
      "protocol_md" => run.protocol_md,
      "rubric_json" => run.rubric_json || %{},
      "task_json" => run.task_json || %{},
      "report_html" => run.report_html,
      "run_log" => run.run_log,
      "input_bundle_sha256" => hash_term(capsule.data_files || [])
    }

    %{
      "attempt_id" => attempt_id(run.run_id),
      "capsule_id" => capsule_id(capsule.capsule_id),
      "version_id" => version,
      "harness_id" => harness.harness_id,
      "repeat_group_id" => Reliability.single_repeat_group(),
      "attempt_ordinal" => 1,
      "status" => attempt_status(run.status),
      "score_status" => score_status(run),
      "raw_score" => run.raw_score,
      "normalized_score" => run.normalized_score,
      "score_source" => run.score_source,
      "solved" => run.status == :validated,
      "answer_text" => run.final_answer_md,
      "answer_hash" => answer_hash(run),
      "verdict_json" => run.verdict_json || %{},
      "artifact_manifest" =>
        artifact_manifest(run_source["artifact_manifest"] || run.artifact_source),
      "run_source" =>
        run_source
        |> Map.put("artifact_source", run.artifact_source || %{})
        |> Map.put("harness_bundle_hash", harness.normalized_bundle_hash)
        |> Map.put("bbh", %{
          "legacy_run_id" => run.run_id,
          "legacy_capsule_id" => capsule.capsule_id,
          "legacy_genome_id" => run.genome_id,
          "assignment_ref" => run.assignment_ref,
          "canonical_run_id" => run.canonical_run_id,
          "split" => run.split
        }),
      "workspace_source" => workspace_source,
      "submitted_at" => run.inserted_at,
      "validated_at" => if(run.status in [:validated, :rejected], do: run.updated_at)
    }
  end

  defp validation_attrs(%Validation{} = validation, %Attempt{} = attempt) do
    review_source =
      (validation.review_source || %{})
      |> Map.put("bbh", %{
        "legacy_validation_id" => validation.validation_id,
        "legacy_run_id" => validation.run_id,
        "canonical_review_id" => validation.canonical_review_id,
        "report_html" => validation.report_html,
        "run_log" => validation.run_log
      })

    %{
      "validation_id" => validation_id(validation.validation_id),
      "attempt_id" => attempt.attempt_id,
      "capsule_id" => attempt.capsule_id,
      "role" => Atom.to_string(validation.role),
      "method" => Atom.to_string(validation.method),
      "result" => Atom.to_string(validation.result),
      "reproduced_raw_score" => validation.reproduced_raw_score,
      "reproduced_normalized_score" => validation.reproduced_normalized_score,
      "tolerance_raw_abs" => validation.tolerance_raw_abs || 0.01,
      "summary_md" => validation.summary || "Review recorded.",
      "verdict_json" => validation.verdict_json || %{},
      "review_source" => review_source
    }
  end

  defp review_attempt_attrs(%ReviewSubmission{} = submission, %Capsule{} = capsule, harness) do
    status =
      case submission.decision do
        decision when decision in [:approve, :approve_with_edits] -> "validated"
        :changes_requested -> "validation_pending"
        :reject -> "rejected"
      end

    %{
      "attempt_id" => review_attempt_id(submission.submission_id),
      "capsule_id" => capsule_id(capsule.capsule_id),
      "version_id" => version_id(capsule.capsule_id),
      "harness_id" => harness.harness_id,
      "solver_wallet_address" => submission.reviewer_wallet,
      "repeat_group_id" => "review:#{submission.request_id}",
      "attempt_ordinal" => 1,
      "status" => status,
      "score_status" => if(status == "rejected", do: "rejected", else: "unscored"),
      "solved" => status == "validated",
      "answer_text" => submission.summary_md,
      "answer_hash" => hash_term(review_submission_source(submission)),
      "verdict_json" => review_verdict(submission),
      "artifact_manifest" => %{},
      "run_source" => %{
        "bbh_review_submission" => review_submission_source(submission)
      },
      "workspace_source" => %{},
      "submitted_at" => submission.inserted_at,
      "validated_at" => if(status in ["validated", "rejected"], do: submission.updated_at)
    }
  end

  defp review_validation_attrs(%ReviewSubmission{} = submission, %Attempt{} = attempt) do
    %{
      "validation_id" => review_validation_id(submission.submission_id),
      "attempt_id" => attempt.attempt_id,
      "capsule_id" => attempt.capsule_id,
      "validator_wallet_address" => submission.reviewer_wallet,
      "role" => "reviewer",
      "method" => "manual",
      "result" => review_validation_result(submission.decision),
      "summary_md" => submission.summary_md,
      "verdict_json" => review_verdict(submission),
      "review_source" => %{
        "bbh_review_submission" => review_submission_source(submission)
      }
    }
  end

  defp review_submission_source(%ReviewSubmission{} = submission) do
    %{
      "submission_id" => submission.submission_id,
      "request_id" => submission.request_id,
      "legacy_capsule_id" => submission.capsule_id,
      "reviewer_wallet" => submission.reviewer_wallet,
      "decision" => atom_string(submission.decision),
      "checklist_json" => submission.checklist_json || %{},
      "suggested_edits_json" => submission.suggested_edits_json || %{},
      "certificate_payload" => submission.certificate_payload || %{},
      "review_node_id" => submission.review_node_id
    }
  end

  defp review_verdict(%ReviewSubmission{} = submission) do
    %{
      "decision" => atom_string(submission.decision),
      "certificate_review_id" => submission.review_node_id
    }
  end

  defp review_validation_result(decision) when decision in [:approve, :approve_with_edits],
    do: "confirmed"

  defp review_validation_result(:changes_requested), do: "needs_revision"
  defp review_validation_result(:reject), do: "rejected"

  defp bbh_capsule_source(%Capsule{} = capsule) do
    %{
      "legacy_capsule_id" => capsule.capsule_id,
      "split" => capsule.split,
      "provider" => capsule.provider,
      "provider_ref" => capsule.provider_ref,
      "family_ref" => capsule.family_ref,
      "instance_ref" => capsule.instance_ref,
      "language" => capsule.language,
      "mode" => capsule.mode,
      "assignment_policy" => capsule.assignment_policy,
      "task_json" => capsule.task_json || %{},
      "artifact_source" => capsule.artifact_source || %{},
      "data_manifest" => %{"files" => capsule.data_files || []},
      "recommended_genome_source" => capsule.recommended_genome_source || %{},
      "genome_notes_md" => capsule.genome_notes_md,
      "publication_artifact_id" => capsule.publication_artifact_id,
      "publication_review_id" => capsule.publication_review_id,
      "certificate_status" => atom_string(capsule.certificate_status || :none),
      "certificate_review_id" => capsule.certificate_review_id,
      "certificate_scope" => capsule.certificate_scope,
      "certificate_expires_at" => encode_datetime(capsule.certificate_expires_at),
      "seed" => capsule.seed,
      "parent_id" => capsule.parent_id
    }
  end

  defp public_capsule?(%Capsule{split: "draft"}), do: false
  defp public_capsule?(%Capsule{split: "challenge", published_at: nil}), do: false
  defp public_capsule?(%Capsule{split: split}) when split in @public_splits, do: true
  defp public_capsule?(_capsule), do: false

  defp benchmark_workflow_state(capsule) do
    cond do
      public_capsule?(capsule) ->
        "published"

      capsule.workflow_state in [:review_ready, :in_review, :approved, :rejected, :retired] ->
        Atom.to_string(capsule.workflow_state)

      true ->
        "authoring"
    end
  end

  defp benchmark_visibility(capsule) do
    cond do
      public_capsule?(capsule) -> "public"
      capsule.workflow_state in [:review_ready, :in_review, :approved] -> "private_review"
      true -> "draft"
    end
  end

  defp benchmark_version_status(capsule) do
    cond do
      public_capsule?(capsule) ->
        "published"

      capsule.workflow_state in [:review_ready, :approved] ->
        Atom.to_string(capsule.workflow_state)

      capsule.workflow_state == :retired ->
        "retired"

      true ->
        "draft"
    end
  end

  defp attempt_status(:validated), do: "validated"
  defp attempt_status(:rejected), do: "rejected"
  defp attempt_status(:failed), do: "failed"
  defp attempt_status(:running), do: "running"
  defp attempt_status(_status), do: "submitted"

  defp score_status(%Run{status: :rejected}), do: "rejected"
  defp score_status(%Run{normalized_score: score}) when is_number(score), do: "scored"
  defp score_status(_run), do: "unscored"

  defp runner_kind(value)
       when value in ~w(hermes openclaw regents codex claude skydiscover gemini opencode manual_human custom_local),
       do: value

  defp runner_kind(_value), do: "custom_local"

  defp answer_hash(%Run{final_answer_md: answer}) when is_binary(answer) and answer != "",
    do: hash_term(answer)

  defp answer_hash(%Run{verdict_json: verdict}) when is_map(verdict), do: hash_term(verdict)
  defp answer_hash(_run), do: nil

  defp artifact_manifest(value) when is_map(value), do: value
  defp artifact_manifest(value) when is_list(value), do: %{"files" => value}
  defp artifact_manifest(_value), do: %{}

  defp capsule_id(id), do: stable_id("bench_bbh", id)
  defp version_id(id), do: stable_id("benchv_bbh", id)
  defp harness_id(id), do: stable_id("harness_bbh", id)
  defp attempt_id(id), do: stable_id("attempt_bbh", id)
  defp validation_id(id), do: stable_id("validation_bbh", id)
  defp review_harness_id, do: stable_id("harness_bbh_review", "certificate")
  defp review_attempt_id(id), do: stable_id("attempt_bbh_review", id)
  defp review_validation_id(id), do: stable_id("validation_bbh_review", id)

  defp stable_id(prefix, value) do
    suffix =
      value
      |> to_string()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 24)

    "#{prefix}_#{suffix}"
  end

  defp hash_term(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
    |> Base.encode16(case: :lower)
  end

  defp atom_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_string(value), do: value

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
