defmodule TechTree.Repo.Migrations.AddBbhReviewWorkflow do
  use Ecto.Migration

  def change do
    alter table(:bbh_capsules) do
      add :owner_wallet_address, :text
      add :source_node_id, :bigint
      add :seed, :text
      add :parent_id, :bigint
      add :workflow_state, :text, null: false, default: "authoring"
      add :notebook_py, :text
      add :capsule_source, :map, null: false, default: %{}
      add :recommended_genome_source, :map, null: false, default: %{}
      add :genome_notes_md, :text
      add :certificate_status, :text, null: false, default: "none"
      add :certificate_review_id, :text
      add :certificate_scope, :text
      add :certificate_expires_at, :utc_datetime_usec
    end

    create index(:bbh_capsules, [:owner_wallet_address])
    create index(:bbh_capsules, [:workflow_state])
    create index(:bbh_capsules, [:certificate_status])
    create index(:bbh_capsules, [:certificate_review_id])

    create table(:bbh_draft_proposals, primary_key: false) do
      add :proposal_id, :text, primary_key: true

      add :capsule_id,
          references(:bbh_capsules, column: :capsule_id, type: :text, on_delete: :delete_all),
          null: false

      add :proposer_wallet_address, :text, null: false
      add :summary, :text, null: false
      add :workspace_bundle, :map, null: false, default: %{}
      add :patch_json, :map, null: false, default: %{}
      add :workspace_manifest_hash, :text, null: false
      add :status, :text, null: false, default: "open"

      timestamps()
    end

    create index(:bbh_draft_proposals, [:capsule_id])
    create index(:bbh_draft_proposals, [:status])

    create table(:bbh_reviewer_profiles, primary_key: false) do
      add :wallet_address, :text, primary_key: true
      add :orcid_id, :text
      add :orcid_auth_kind, :text
      add :orcid_name, :text
      add :vetting_status, :text, null: false, default: "pending"
      add :domain_tags, {:array, :text}, null: false, default: []
      add :payout_wallet, :text
      add :experience_summary, :text
      add :vetted_by, :text
      add :vetted_at, :utc_datetime_usec

      timestamps()
    end

    create index(:bbh_reviewer_profiles, [:orcid_id])
    create index(:bbh_reviewer_profiles, [:vetting_status])

    create table(:bbh_orcid_link_requests, primary_key: false) do
      add :request_id, :text, primary_key: true
      add :wallet_address, :text, null: false
      add :state, :text, null: false, default: "pending"
      add :expires_at, :utc_datetime_usec, null: false
      add :authenticated_at, :utc_datetime_usec

      timestamps()
    end

    create index(:bbh_orcid_link_requests, [:wallet_address])
    create index(:bbh_orcid_link_requests, [:state])

    create table(:bbh_review_requests, primary_key: false) do
      add :request_id, :text, primary_key: true

      add :capsule_id,
          references(:bbh_capsules, column: :capsule_id, type: :text, on_delete: :delete_all),
          null: false

      add :review_kind, :text, null: false
      add :visibility, :text, null: false, default: "public_claim"
      add :state, :text, null: false, default: "open"
      add :claimed_by_wallet, :text
      add :fee_quote_usdc, :text
      add :holdback_usdc, :text
      add :due_at, :utc_datetime_usec
      add :closed_at, :utc_datetime_usec

      timestamps()
    end

    create index(:bbh_review_requests, [:capsule_id])
    create index(:bbh_review_requests, [:state])
    create index(:bbh_review_requests, [:visibility])
    create index(:bbh_review_requests, [:claimed_by_wallet])

    create table(:bbh_review_submissions, primary_key: false) do
      add :submission_id, :text, primary_key: true

      add :request_id,
          references(:bbh_review_requests,
            column: :request_id,
            type: :text,
            on_delete: :delete_all
          ),
          null: false

      add :capsule_id,
          references(:bbh_capsules, column: :capsule_id, type: :text, on_delete: :delete_all),
          null: false

      add :reviewer_wallet, :text, null: false
      add :checklist_json, :map, null: false, default: %{}
      add :suggested_edits_json, :map, null: false, default: %{}
      add :decision, :text, null: false
      add :summary_md, :text, null: false
      add :genome_recommendation_source, :map, null: false, default: %{}
      add :certificate_payload, :map, null: false, default: %{}
      add :review_node_id, :text

      timestamps()
    end

    create index(:bbh_review_submissions, [:request_id])
    create index(:bbh_review_submissions, [:capsule_id])
    create index(:bbh_review_submissions, [:review_node_id])
  end
end
