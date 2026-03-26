defmodule TechTree.Repo.Migrations.CreateBbhV01Tables do
  use Ecto.Migration

  def change do
    create table(:bbh_capsules, primary_key: false) do
      add :capsule_id, :text, primary_key: true
      add :provider, :text, null: false
      add :provider_ref, :text, null: false
      add :family_ref, :text
      add :instance_ref, :text
      add :split, :text, null: false
      add :language, :text, null: false
      add :mode, :text, null: false
      add :assignment_policy, :text, null: false
      add :title, :text, null: false
      add :hypothesis, :text, null: false
      add :protocol_md, :text, null: false
      add :rubric_json, :map, null: false, default: %{}
      add :task_json, :map, null: false, default: %{}
      add :data_files, {:array, :map}, null: false, default: []
      add :artifact_source, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:bbh_capsules, [:split])
    create index(:bbh_capsules, [:provider, :provider_ref])
    create index(:bbh_capsules, [:assignment_policy])

    create table(:bbh_assignments, primary_key: false) do
      add :assignment_ref, :text, primary_key: true

      add :capsule_id,
          references(:bbh_capsules, column: :capsule_id, type: :text, on_delete: :delete_all),
          null: false

      add :split, :text, null: false
      add :status, :text, null: false
      add :agent_wallet_address, :text
      add :agent_token_id, :text
      add :origin, :text, null: false, default: "auto_or_select:auto"
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:bbh_assignments, [:capsule_id])
    create index(:bbh_assignments, [:split])
    create index(:bbh_assignments, [:status])

    create table(:bbh_genomes, primary_key: false) do
      add :genome_id, :text, primary_key: true
      add :label, :text
      add :parent_genome_ref, :text
      add :model_id, :text, null: false
      add :harness_type, :text, null: false
      add :harness_version, :text, null: false
      add :prompt_pack_version, :text, null: false
      add :skill_pack_version, :text, null: false
      add :tool_profile, :text, null: false
      add :runtime_image, :text, null: false
      add :helper_code_hash, :text
      add :data_profile, :text
      add :axes, :map, null: false, default: %{}
      add :notes, :text
      add :normalized_bundle_hash, :text, null: false
      add :source, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bbh_genomes, [:normalized_bundle_hash])
    create index(:bbh_genomes, [:model_id])
    create index(:bbh_genomes, [:harness_type])

    create table(:bbh_runs, primary_key: false) do
      add :run_id, :text, primary_key: true

      add :capsule_id,
          references(:bbh_capsules, column: :capsule_id, type: :text, on_delete: :restrict),
          null: false

      add :assignment_ref,
          references(:bbh_assignments,
            column: :assignment_ref,
            type: :text,
            on_delete: :nilify_all
          )

      add :genome_id,
          references(:bbh_genomes, column: :genome_id, type: :text, on_delete: :restrict),
          null: false

      add :canonical_run_id, :text
      add :executor_type, :text, null: false
      add :harness_type, :text, null: false
      add :harness_version, :text, null: false
      add :split, :text, null: false
      add :status, :text, null: false
      add :raw_score, :float
      add :normalized_score, :float
      add :score_source, :text, null: false, default: "submitted"
      add :analysis_py, :text, null: false
      add :protocol_md, :text, null: false
      add :rubric_json, :map, null: false, default: %{}
      add :task_json, :map, null: false, default: %{}
      add :verdict_json, :map, null: false, default: %{}
      add :final_answer_md, :text
      add :report_html, :text
      add :run_log, :text
      add :artifact_source, :map
      add :genome_source, :map, null: false, default: %{}
      add :run_source, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:bbh_runs, [:capsule_id])
    create index(:bbh_runs, [:assignment_ref])
    create index(:bbh_runs, [:genome_id])
    create index(:bbh_runs, [:split])
    create index(:bbh_runs, [:status])
    create index(:bbh_runs, [:normalized_score])
    create index(:bbh_runs, [:canonical_run_id])

    create table(:bbh_validations, primary_key: false) do
      add :validation_id, :text, primary_key: true

      add :run_id, references(:bbh_runs, column: :run_id, type: :text, on_delete: :delete_all),
        null: false

      add :canonical_review_id, :text
      add :role, :text, null: false
      add :method, :text, null: false
      add :result, :text, null: false
      add :reproduced_raw_score, :float
      add :reproduced_normalized_score, :float
      add :tolerance_raw_abs, :float, null: false, default: 0.01
      add :summary, :text, null: false
      add :review_source, :map, null: false, default: %{}
      add :verdict_json, :map
      add :report_html, :text
      add :run_log, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:bbh_validations, [:run_id])
    create index(:bbh_validations, [:role])
    create index(:bbh_validations, [:result])
    create index(:bbh_validations, [:canonical_review_id])
  end
end
