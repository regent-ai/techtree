defmodule TechTree.Repo.Migrations.AddManifestV1Tables do
  use Ecto.Migration

  def change do
    create table(:manifest_nodes, primary_key: false) do
      add :id, :text, primary_key: true
      add :node_type, :integer, null: false
      add :author, :text, null: false
      add :subject_id, :text
      add :aux_id, :text
      add :payload_hash, :text, null: false
      add :manifest_cid, :text
      add :payload_cid, :text
      add :schema_version, :integer, null: false
      add :tx_hash, :text
      add :block_number, :bigint
      add :block_time, :utc_datetime_usec
      add :verification_status, :text, null: false, default: "verified"
      add :verification_error, :text
      add :header, :map, null: false, default: %{}
      add :manifest, :map, null: false, default: %{}
      add :payload_index, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:manifest_nodes, [:node_type])
    create index(:manifest_nodes, [:subject_id])
    create index(:manifest_nodes, [:author])

    create table(:manifest_artifacts, primary_key: false) do
      add :id, references(:manifest_nodes, type: :text, on_delete: :delete_all), primary_key: true
      add :kind, :text, null: false
      add :title, :text, null: false
      add :summary, :text, null: false
      add :has_eval, :boolean, null: false, default: false
      add :eval_mode, :text

      timestamps(type: :utc_datetime_usec)
    end

    create table(:manifest_artifact_edges) do
      add :child_id, references(:manifest_nodes, type: :text, on_delete: :delete_all), null: false

      add :parent_id, references(:manifest_nodes, type: :text, on_delete: :delete_all),
        null: false

      add :relation, :text, null: false
      add :note, :text

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:manifest_artifact_edges, [:child_id])
    create index(:manifest_artifact_edges, [:parent_id])

    create unique_index(:manifest_artifact_edges, [:child_id, :parent_id, :relation],
             name: :manifest_artifact_edges_unique_idx
           )

    create table(:manifest_runs, primary_key: false) do
      add :id, references(:manifest_nodes, type: :text, on_delete: :delete_all), primary_key: true
      add :artifact_id, :text, null: false
      add :executor_type, :text, null: false
      add :executor_id, :text, null: false
      add :executor_harness_kind, :text
      add :executor_harness_profile, :text
      add :origin_kind, :text
      add :origin_transport, :text
      add :origin_session_id, :text
      add :status, :text, null: false
      add :score, :float

      timestamps(type: :utc_datetime_usec)
    end

    create index(:manifest_runs, [:artifact_id])
    create index(:manifest_runs, [:status])
    create index(:manifest_runs, [:executor_harness_kind])
    create index(:manifest_runs, [:executor_harness_profile])
    create index(:manifest_runs, [:origin_kind])
    create index(:manifest_runs, [:origin_transport])
    create index(:manifest_runs, [:origin_session_id])

    create table(:manifest_reviews, primary_key: false) do
      add :id, references(:manifest_nodes, type: :text, on_delete: :delete_all), primary_key: true
      add :target_type, :text, null: false
      add :target_id, :text, null: false
      add :kind, :text, null: false
      add :method, :text, null: false
      add :result, :text, null: false
      add :scope_level, :text, null: false
      add :scope_path, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:manifest_reviews, [:target_id])
    create index(:manifest_reviews, [:kind])
    create index(:manifest_reviews, [:result])

    create table(:manifest_payload_files) do
      add :node_id, references(:manifest_nodes, type: :text, on_delete: :delete_all), null: false
      add :path, :text, null: false
      add :sha256, :text, null: false
      add :size, :bigint, null: false
      add :media_type, :text, null: false
      add :role, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:manifest_payload_files, [:node_id])

    create unique_index(:manifest_payload_files, [:node_id, :path],
             name: :manifest_payload_files_unique_idx
           )

    create table(:manifest_sources) do
      add :node_id, references(:manifest_nodes, type: :text, on_delete: :delete_all), null: false
      add :ordinal, :integer, null: false
      add :kind, :text, null: false
      add :ref, :text, null: false
      add :license, :text
      add :note, :text

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:manifest_sources, [:node_id])

    create unique_index(:manifest_sources, [:node_id, :ordinal],
             name: :manifest_sources_unique_idx
           )

    create table(:manifest_claims) do
      add :artifact_id, references(:manifest_nodes, type: :text, on_delete: :delete_all),
        null: false

      add :ordinal, :integer, null: false
      add :text, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:manifest_claims, [:artifact_id])

    create unique_index(:manifest_claims, [:artifact_id, :ordinal],
             name: :manifest_claims_unique_idx
           )

    create table(:manifest_findings) do
      add :review_id, references(:manifest_nodes, type: :text, on_delete: :delete_all),
        null: false

      add :ordinal, :integer, null: false
      add :code, :text, null: false
      add :severity, :text, null: false
      add :message, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:manifest_findings, [:review_id])

    create unique_index(:manifest_findings, [:review_id, :ordinal],
             name: :manifest_findings_unique_idx
           )

    create table(:manifest_node_state, primary_key: false) do
      add :node_id, references(:manifest_nodes, type: :text, on_delete: :delete_all),
        primary_key: true

      add :validated, :boolean, null: false, default: false
      add :challenged, :boolean, null: false, default: false
      add :retired, :boolean, null: false, default: false
      add :latest_review_result, :text

      timestamps(type: :utc_datetime_usec)
    end

    create table(:manifest_rejected_ingests) do
      add :node_id, :text
      add :node_type, :integer
      add :manifest_cid, :text
      add :payload_cid, :text
      add :reason, :text, null: false
      add :header, :map, null: false, default: %{}
      add :manifest, :map, null: false, default: %{}
      add :payload_index, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:manifest_rejected_ingests, [:node_id])
    create index(:manifest_rejected_ingests, [:manifest_cid])
  end
end
