defmodule TechTree.Repo.Migrations.CreateBenchmarkCapsules do
  use Ecto.Migration

  def up do
    create table(:benchmark_capsules, primary_key: false) do
      add :capsule_id, :text, primary_key: true
      add :legacy_bbh_capsule_id, :text
      add :source_node_id, references(:nodes, on_delete: :nilify_all)
      add :owner_agent_id, references(:agent_identities, on_delete: :nilify_all)
      add :owner_wallet_address, :text

      add :domain, :text, null: false
      add :field, :text
      add :family_ref, :text
      add :provider, :text
      add :provider_ref, :text
      add :import_batch_id, :text

      add :title, :text, null: false
      add :summary_md, :text
      add :question_md, :text, null: false
      add :difficulty_label, :text
      add :human_baseline_status, :text, null: false, default: "unknown"

      add :ground_truth_policy, :text, null: false
      add :answer_format, :map, null: false, default: %{}
      add :allowed_tools_policy, :map, null: false, default: %{}
      add :external_resource_policy, :map, null: false, default: %{}
      add :scoring_policy, :map, null: false, default: %{}
      add :anti_cheat_policy, :map, null: false, default: %{}

      add :workflow_state, :text, null: false, default: "authoring"
      add :visibility, :text, null: false, default: "draft"
      add :current_version_id, :text
      add :published_at, :utc_datetime_usec
      add :retired_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:benchmark_capsules, [:legacy_bbh_capsule_id],
             where: "legacy_bbh_capsule_id is not null"
           )

    create index(:benchmark_capsules, [:domain, :field])
    create index(:benchmark_capsules, [:workflow_state])
    create index(:benchmark_capsules, [:visibility])
    create index(:benchmark_capsules, [:provider, :provider_ref])

    create table(:benchmark_capsule_versions, primary_key: false) do
      add :version_id, :text, primary_key: true

      add :capsule_id,
          references(:benchmark_capsules,
            column: :capsule_id,
            type: :text,
            on_delete: :delete_all
          ),
          null: false

      add :version_label, :text, null: false
      add :version_status, :text, null: false, default: "draft"

      add :manifest_cid, :text
      add :manifest_sha256, :text
      add :manifest_uri, :text
      add :input_bundle_cid, :text
      add :input_bundle_sha256, :text
      add :validation_notebook_cid, :text
      add :validation_notebook_sha256, :text
      add :redacted_validation_notebook_cid, :text
      add :ground_truth_manifest_hash, :text
      add :ground_truth_storage_policy, :map, null: false, default: %{}
      add :environment_lock_ref, :map, null: false, default: %{}
      add :data_manifest, :map, null: false, default: %{}
      add :capsule_source, :map, null: false, default: %{}

      add :publication_node_id, references(:nodes, on_delete: :nilify_all)
      add :chain_tx_hash, :text
      add :chain_id, :integer
      add :anchored_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:benchmark_capsule_versions, [:capsule_id, :version_label])
    create index(:benchmark_capsule_versions, [:version_status])
    create index(:benchmark_capsule_versions, [:manifest_cid])

    create table(:benchmark_harnesses, primary_key: false) do
      add :harness_id, :text, primary_key: true
      add :owner_agent_id, references(:agent_identities, on_delete: :nilify_all)
      add :name, :text, null: false
      add :description_md, :text
      add :domain, :text
      add :runner_kind, :text, null: false
      add :model_id, :text
      add :agent_runtime, :text
      add :harness_version, :text, null: false
      add :prompt_pack_ref, :map, null: false, default: %{}
      add :skill_pack_refs, {:array, :map}, null: false, default: []
      add :tool_profile, :map, null: false, default: %{}
      add :runtime_image, :text
      add :dependency_lock_ref, :map, null: false, default: %{}
      add :workspace_policy, :map, null: false, default: %{}
      add :normalized_bundle_hash, :text, null: false
      add :source, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:benchmark_harnesses, [:normalized_bundle_hash])
    create index(:benchmark_harnesses, [:runner_kind])
    create index(:benchmark_harnesses, [:model_id])

    create table(:benchmark_attempts, primary_key: false) do
      add :attempt_id, :text, primary_key: true

      add :capsule_id,
          references(:benchmark_capsules,
            column: :capsule_id,
            type: :text,
            on_delete: :restrict
          ),
          null: false

      add :version_id,
          references(:benchmark_capsule_versions,
            column: :version_id,
            type: :text,
            on_delete: :restrict
          ),
          null: false

      add :harness_id,
          references(:benchmark_harnesses,
            column: :harness_id,
            type: :text,
            on_delete: :restrict
          ),
          null: false

      add :solver_agent_id, references(:agent_identities, on_delete: :nilify_all)
      add :solver_wallet_address, :text

      add :repeat_group_id, :text
      add :attempt_ordinal, :integer, null: false, default: 1
      add :status, :text, null: false, default: "submitted"
      add :score_status, :text, null: false, default: "unscored"
      add :raw_score, :float
      add :normalized_score, :float
      add :score_source, :text
      add :solved, :boolean

      add :answer_text, :text
      add :answer_json, :map
      add :answer_hash, :text
      add :verdict_json, :map, null: false, default: %{}

      add :run_bundle_cid, :text
      add :run_bundle_sha256, :text
      add :solver_notebook_cid, :text
      add :report_cid, :text
      add :tool_calls_cid, :text
      add :log_cid, :text
      add :artifact_manifest, :map, null: false, default: %{}

      add :runtime_seconds, :integer
      add :cost_usd_micros, :bigint
      add :tokens_input, :bigint
      add :tokens_output, :bigint
      add :tool_install_events_count, :integer, null: false, default: 0
      add :external_resource_call_count, :integer, null: false, default: 0

      add :run_source, :map, null: false, default: %{}
      add :workspace_source, :map, null: false, default: %{}

      add :submitted_at, :utc_datetime_usec
      add :validated_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:benchmark_attempts, [:capsule_id, :version_id])
    create index(:benchmark_attempts, [:harness_id])
    create index(:benchmark_attempts, [:repeat_group_id])
    create index(:benchmark_attempts, [:normalized_score])
    create index(:benchmark_attempts, [:solved])

    create table(:benchmark_validations, primary_key: false) do
      add :validation_id, :text, primary_key: true

      add :attempt_id,
          references(:benchmark_attempts,
            column: :attempt_id,
            type: :text,
            on_delete: :delete_all
          ),
          null: false

      add :capsule_id,
          references(:benchmark_capsules,
            column: :capsule_id,
            type: :text,
            on_delete: :delete_all
          ),
          null: false

      add :validator_agent_id, references(:agent_identities, on_delete: :nilify_all)
      add :validator_wallet_address, :text
      add :role, :text, null: false
      add :method, :text, null: false
      add :result, :text, null: false
      add :reproduced_raw_score, :float
      add :reproduced_normalized_score, :float
      add :tolerance_raw_abs, :float, null: false, default: 0.01
      add :summary_md, :text, null: false
      add :validation_notebook_cid, :text
      add :verdict_json, :map, null: false, default: %{}
      add :review_source, :map, null: false, default: %{}
      add :review_node_id, references(:nodes, on_delete: :nilify_all)
      add :chain_tx_hash, :text
      add :chain_id, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create index(:benchmark_validations, [:attempt_id])
    create index(:benchmark_validations, [:capsule_id])
    create index(:benchmark_validations, [:role, :result])

    create table(:benchmark_reliability_summaries, primary_key: false) do
      add :summary_id, :text, primary_key: true

      add :capsule_id,
          references(:benchmark_capsules,
            column: :capsule_id,
            type: :text,
            on_delete: :delete_all
          ),
          null: false

      add :version_id,
          references(:benchmark_capsule_versions,
            column: :version_id,
            type: :text,
            on_delete: :delete_all
          ),
          null: false

      add :harness_id,
          references(:benchmark_harnesses,
            column: :harness_id,
            type: :text,
            on_delete: :delete_all
          ),
          null: false

      add :repeat_group_id, :text, null: false

      add :attempt_count, :integer, null: false, default: 0
      add :solve_count, :integer, null: false, default: 0
      add :solve_rate, :float, null: false, default: 0.0
      add :reliable, :boolean, null: false, default: false
      add :brittle, :boolean, null: false, default: false
      add :answer_variance, :map, null: false, default: %{}
      add :median_runtime_seconds, :float
      add :p90_runtime_seconds, :float
      add :median_cost_usd_micros, :bigint
      add :validation_confirmed_count, :integer, null: false, default: 0
      add :last_attempt_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:benchmark_reliability_summaries, [
             :capsule_id,
             :version_id,
             :harness_id,
             :repeat_group_id
           ])

    create index(:benchmark_reliability_summaries, [:solve_rate])
    create index(:benchmark_reliability_summaries, [:reliable])

    create table(:benchmark_artifacts, primary_key: false) do
      add :artifact_id, :text, primary_key: true

      add :capsule_id,
          references(:benchmark_capsules,
            column: :capsule_id,
            type: :text,
            on_delete: :nilify_all
          )

      add :version_id,
          references(:benchmark_capsule_versions,
            column: :version_id,
            type: :text,
            on_delete: :nilify_all
          )

      add :attempt_id,
          references(:benchmark_attempts,
            column: :attempt_id,
            type: :text,
            on_delete: :nilify_all
          )

      add :validation_id,
          references(:benchmark_validations,
            column: :validation_id,
            type: :text,
            on_delete: :nilify_all
          )

      add :kind, :text, null: false
      add :name, :text
      add :cid, :text
      add :uri, :text
      add :sha256, :text
      add :byte_size, :bigint
      add :content_type, :text
      add :storage_provider, :text, null: false, default: "lighthouse"
      add :visibility, :text, null: false, default: "public"
      add :encryption_meta, :map, null: false, default: %{}
      add :license, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:benchmark_artifacts, [:kind])
    create index(:benchmark_artifacts, [:cid])
    create index(:benchmark_artifacts, [:capsule_id])

    create_benchmark_constraints()
  end

  def down do
    raise "hard cutover only"
  end

  defp create_benchmark_constraints do
    create constraint(:benchmark_capsules, :benchmark_capsules_domain_check,
             check:
               "domain IN ('bbh', 'bioinformatics', 'computational_biology', 'science_task', 'code', 'math', 'agent_skill', 'other')"
           )

    create constraint(:benchmark_capsules, :benchmark_capsules_human_baseline_status_check,
             check:
               "human_baseline_status IN ('unknown', 'human_solvable', 'human_difficult', 'expert_only', 'unsolved', 'not_applicable')"
           )

    create constraint(:benchmark_capsules, :benchmark_capsules_ground_truth_policy_check,
             check:
               "ground_truth_policy IN ('public', 'hidden_server', 'reviewer_only', 'deterministic_oracle', 'external_oracle', 'metadata_scrambled', 'synthetic')"
           )

    create constraint(:benchmark_capsules, :benchmark_capsules_workflow_state_check,
             check:
               "workflow_state IN ('authoring', 'review_ready', 'in_review', 'approved', 'published', 'rejected', 'retired')"
           )

    create constraint(:benchmark_capsules, :benchmark_capsules_visibility_check,
             check: "visibility IN ('draft', 'private_review', 'public', 'paid_access')"
           )

    create constraint(:benchmark_capsule_versions, :benchmark_capsule_versions_status_check,
             check:
               "version_status IN ('draft', 'review_ready', 'approved', 'published', 'superseded', 'retired')"
           )

    create constraint(:benchmark_harnesses, :benchmark_harnesses_runner_kind_check,
             check:
               "runner_kind IN ('hermes', 'openclaw', 'regents', 'codex', 'claude', 'skydiscover', 'gemini', 'opencode', 'manual_human', 'custom_local')"
           )

    create constraint(:benchmark_attempts, :benchmark_attempts_status_check,
             check:
               "status IN ('created', 'running', 'submitted', 'scored', 'validation_pending', 'validated', 'rejected', 'failed')"
           )

    create constraint(:benchmark_attempts, :benchmark_attempts_score_status_check,
             check: "score_status IN ('unscored', 'scored', 'rejected')"
           )

    create constraint(:benchmark_validations, :benchmark_validations_role_check,
             check: "role IN ('official', 'community', 'reviewer', 'author', 'oracle')"
           )

    create constraint(:benchmark_validations, :benchmark_validations_method_check,
             check:
               "method IN ('replay', 'manual', 'replication', 'oracle', 'hidden_truth_check')"
           )

    create constraint(:benchmark_validations, :benchmark_validations_result_check,
             check:
               "result IN ('confirmed', 'rejected', 'mixed', 'needs_revision', 'inconclusive')"
           )

    create constraint(:benchmark_artifacts, :benchmark_artifacts_kind_check,
             check:
               "kind IN ('input_bundle', 'data_manifest', 'validation_notebook', 'redacted_validation_notebook', 'ground_truth_manifest', 'run_bundle', 'solver_notebook', 'tool_calls_log', 'run_log', 'report', 'review_packet', 'skill_bundle', 'harness_bundle')"
           )

    create constraint(:benchmark_artifacts, :benchmark_artifacts_visibility_check,
             check: "visibility IN ('public', 'paid', 'reviewer_only', 'private')"
           )
  end
end
