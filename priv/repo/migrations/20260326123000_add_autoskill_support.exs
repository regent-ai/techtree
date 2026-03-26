defmodule TechTree.Repo.Migrations.AddAutoskillSupport do
  use Ecto.Migration
  @disable_ddl_transaction true

  def change do
    execute(
      "ALTER TYPE node_kind ADD VALUE IF NOT EXISTS 'eval'",
      "SELECT 1"
    )

    create table(:node_bundles) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :bundle_type, :string, null: false
      add :access_mode, :string, null: false
      add :preview_md, :text
      add :bundle_manifest, :map, null: false
      add :primary_file, :string
      add :marimo_entrypoint, :string, null: false
      add :bundle_uri, :string
      add :bundle_cid, :string
      add :bundle_hash, :string
      add :encrypted_bundle_uri, :string
      add :encrypted_bundle_cid, :string
      add :encryption_meta, :map
      add :payment_rail, :string
      add :access_policy, :map

      timestamps()
    end

    create unique_index(:node_bundles, [:node_id])

    create table(:autoskill_results) do
      add :skill_node_id, references(:nodes, on_delete: :delete_all), null: false
      add :eval_node_id, references(:nodes, on_delete: :delete_all), null: false
      add :executor_agent_id, references(:agent_identities, on_delete: :nothing), null: false
      add :runtime_kind, :string, null: false
      add :status, :string, null: false, default: "complete"
      add :trial_count, :integer, null: false, default: 1
      add :raw_score, :float, null: false
      add :normalized_score, :float, null: false
      add :grader_breakdown, :map, null: false, default: %{}
      add :artifacts, :map, null: false, default: %{}
      add :repro_manifest, :map, null: false, default: %{}

      timestamps()
    end

    create index(:autoskill_results, [:skill_node_id])
    create index(:autoskill_results, [:eval_node_id])
    create index(:autoskill_results, [:executor_agent_id])
    create index(:autoskill_results, [:skill_node_id, :eval_node_id])

    create table(:autoskill_reviews) do
      add :skill_node_id, references(:nodes, on_delete: :delete_all), null: false
      add :reviewer_agent_id, references(:agent_identities, on_delete: :nothing), null: false
      add :kind, :string, null: false
      add :result_id, references(:autoskill_results, on_delete: :delete_all)
      add :rating, :float
      add :note, :text
      add :runtime_kind, :string
      add :reported_score, :float
      add :details, :map, null: false, default: %{}

      timestamps()
    end

    create index(:autoskill_reviews, [:skill_node_id])
    create index(:autoskill_reviews, [:reviewer_agent_id])

    create unique_index(
             :autoskill_reviews,
             [:skill_node_id, :reviewer_agent_id, :kind, :result_id],
             name: :autoskill_reviews_dedupe_idx
           )

    create table(:autoskill_listings) do
      add :skill_node_id, references(:nodes, on_delete: :delete_all), null: false
      add :seller_agent_id, references(:agent_identities, on_delete: :nothing), null: false
      add :status, :string, null: false, default: "draft"
      add :payment_rail, :string, null: false
      add :chain_id, :integer, null: false
      add :usdc_token_address, :string, null: false
      add :treasury_address, :string, null: false
      add :seller_payout_address, :string, null: false
      add :price_usdc, :decimal, precision: 30, scale: 6, null: false
      add :treasury_bps, :integer, null: false, default: 100
      add :seller_bps, :integer, null: false, default: 9900
      add :listing_meta, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:autoskill_listings, [:skill_node_id])
  end
end
