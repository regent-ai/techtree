defmodule TechTree.Benchmarks.Importers.ScienceTasks do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Benchmarks.{Artifact, Capsule, CapsuleVersion}
  alias TechTree.Repo
  alias TechTree.ScienceTasks.ScienceTask

  @spec backfill_all(keyword()) :: {:ok, map()} | {:error, term()}
  def backfill_all(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)

    ScienceTask
    |> join(:inner, [task], node in assoc(task, :node))
    |> preload([task, node], node: node)
    |> Repo.all()
    |> upsert_many(dry_run?)
  end

  @spec upsert_task(ScienceTask.t()) :: {:ok, Capsule.t()} | {:error, term()}
  def upsert_task(%ScienceTask{} = task) do
    task = Repo.preload(task, :node)
    capsule_id = capsule_id(task.node_id)
    version_id = version_id(task.node_id)

    Repo.transaction(fn ->
      with {:ok, capsule} <- upsert_capsule(task, capsule_id, version_id),
           {:ok, _version} <- upsert_version(task, capsule_id, version_id),
           {:ok, _artifact} <- upsert_packet_artifact(task, capsule_id, version_id) do
        capsule
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp upsert_many(records, true),
    do: {:ok, %{tasks: length(records), artifacts: length(records)}}

  defp upsert_many(records, false) do
    Enum.reduce_while(records, {:ok, %{tasks: 0, artifacts: 0}}, fn task, {:ok, counts} ->
      case upsert_task(task) do
        {:ok, _capsule} ->
          {:cont, {:ok, %{tasks: counts.tasks + 1, artifacts: counts.artifacts + 1}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp upsert_capsule(task, capsule_id, version_id) do
    attrs = capsule_attrs(task, capsule_id, version_id)

    %Capsule{}
    |> Capsule.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :source_node_id,
           :owner_agent_id,
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

  defp upsert_version(task, capsule_id, version_id) do
    attrs = version_attrs(task, capsule_id, version_id)

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
           :ground_truth_manifest_hash,
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

  defp upsert_packet_artifact(task, capsule_id, version_id) do
    attrs = %{
      "artifact_id" => artifact_id(task.node_id),
      "capsule_id" => capsule_id,
      "version_id" => version_id,
      "kind" => "data_manifest",
      "name" => "#{task.task_slug} task packet",
      "sha256" => task.packet_hash,
      "storage_provider" => "techtree",
      "visibility" => "public",
      "encryption_meta" => %{},
      "license" => nil
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

  defp capsule_attrs(%ScienceTask{} = task, capsule_id, version_id) do
    node = task.node

    %{
      "capsule_id" => capsule_id,
      "source_node_id" => task.node_id,
      "owner_agent_id" => node && node.creator_agent_id,
      "domain" => "science_task",
      "field" => task.science_field,
      "family_ref" => task.science_domain,
      "provider" => "science_tasks",
      "provider_ref" => task.task_slug,
      "title" => node && node.title,
      "summary_md" => node && node.summary,
      "question_md" => instruction_text(task),
      "difficulty_label" => stage_label(task.workflow_state),
      "human_baseline_status" => "expert_only",
      "ground_truth_policy" => "hidden_server",
      "answer_format" => task.structured_output_shape || %{"type" => "structured"},
      "allowed_tools_policy" => %{"review_stage" => Atom.to_string(task.workflow_state)},
      "external_resource_policy" => %{"allowed" => true},
      "scoring_policy" => %{
        "claimed_expert_time" => task.claimed_expert_time,
        "threshold_rationale" => task.threshold_rationale
      },
      "anti_cheat_policy" => %{"notes" => task.anti_cheat_notes},
      "workflow_state" => "published",
      "visibility" => "public",
      "current_version_id" => version_id,
      "published_at" => node && node.inserted_at
    }
  end

  defp version_attrs(%ScienceTask{} = task, capsule_id, version_id) do
    source = science_source(task)

    %{
      "version_id" => version_id,
      "capsule_id" => capsule_id,
      "version_label" => "v1",
      "version_status" => "published",
      "manifest_sha256" => hash_term(source),
      "input_bundle_sha256" => task.packet_hash,
      "ground_truth_manifest_hash" => task.evidence_packet_hash,
      "ground_truth_storage_policy" => %{"policy" => "hidden_server"},
      "environment_lock_ref" => %{"dependency_pinning_status" => task.dependency_pinning_status},
      "data_manifest" => %{"files" => task.packet_files || %{}},
      "capsule_source" => %{"science_task" => source}
    }
  end

  defp science_source(%ScienceTask{} = task) do
    %{
      "legacy_node_id" => task.node_id,
      "science_domain" => task.science_domain,
      "science_field" => task.science_field,
      "task_slug" => task.task_slug,
      "workflow_state" => Atom.to_string(task.workflow_state),
      "structured_output_shape" => task.structured_output_shape,
      "claimed_expert_time" => task.claimed_expert_time,
      "threshold_rationale" => task.threshold_rationale,
      "anti_cheat_notes" => task.anti_cheat_notes,
      "reproducibility_notes" => task.reproducibility_notes,
      "dependency_pinning_status" => task.dependency_pinning_status,
      "canary_status" => task.canary_status,
      "destination_name" => task.destination_name,
      "packet_hash" => task.packet_hash,
      "evidence_packet_hash" => task.evidence_packet_hash,
      "packet_files" => task.packet_files || %{},
      "checklist" => stringify_checklist(task.checklist || %{}),
      "oracle_run" => task.oracle_run,
      "frontier_run" => task.frontier_run,
      "failure_analysis" => task.failure_analysis,
      "harbor_pr_url" => task.harbor_pr_url,
      "review_round_count" => task.review_round_count,
      "open_reviewer_concerns_count" => task.open_reviewer_concerns_count,
      "latest_rerun_after_latest_fix" => task.latest_rerun_after_latest_fix,
      "latest_review_follow_up_note" => task.latest_review_follow_up_note,
      "last_rerun_at" => encode_datetime(task.last_rerun_at),
      "latest_fix_at" => encode_datetime(task.latest_fix_at),
      "any_concern_unanswered" => task.any_concern_unanswered
    }
  end

  defp instruction_text(%ScienceTask{packet_files: %{} = packet_files}) do
    case packet_files["instruction.md"] do
      %{"content" => content} when is_binary(content) and content != "" -> content
      _ -> "Inspect the task packet and review evidence."
    end
  end

  defp instruction_text(_task), do: "Inspect the task packet and review evidence."

  defp stringify_checklist(checklist) do
    Map.new(checklist, fn {key, entry} ->
      value =
        case entry do
          %{"status" => _status} -> entry
          %{status: status, note: note} -> %{"status" => status, "note" => note}
          _ -> %{"status" => "unknown", "note" => nil}
        end

      {to_string(key), value}
    end)
  end

  defp stage_label(nil), do: "authoring"
  defp stage_label(stage) when is_atom(stage), do: Atom.to_string(stage)
  defp stage_label(stage), do: to_string(stage)

  defp capsule_id(node_id), do: stable_id("bench_science", node_id)
  defp version_id(node_id), do: stable_id("benchv_science", node_id)
  defp artifact_id(node_id), do: stable_id("artifact_science_packet", node_id)

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

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
