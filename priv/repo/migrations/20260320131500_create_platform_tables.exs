defmodule TechTree.Repo.Migrations.CreatePlatformTables do
  use Ecto.Migration

  def change do
    create table(:platform_agents) do
      add :slug, :text, null: false
      add :source, :text, null: false
      add :display_name, :text, null: false
      add :summary, :text
      add :status, :text, null: false, default: "active"
      add :owner_address, :text
      add :feature_tags, {:array, :text}, null: false, default: []
      add :chain_id, :bigint
      add :token_id, :decimal
      add :agent_uri, :text
      add :external_url, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_agents, [:slug])
    create index(:platform_agents, [:status])
    create index(:platform_agents, [:owner_address])

    create table(:platform_explorer_tiles) do
      add :coord_key, :text, null: false
      add :x, :integer, null: false
      add :y, :integer, null: false
      add :title, :text, null: false
      add :summary, :text
      add :shader_key, :text
      add :terrain, :text
      add :unlock_status, :text, null: false, default: "imported"
      add :owner_address, :text
      add :metadata, :map, null: false, default: %{}
      add :payment_credit_id, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_explorer_tiles, [:coord_key])
    create index(:platform_explorer_tiles, [:x, :y])

    create table(:platform_name_claims) do
      add :label, :text, null: false
      add :fqdn, :text, null: false
      add :owner_address, :text
      add :status, :text, null: false, default: "claimed"
      add :source, :text, null: false, default: "fixture"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_name_claims, [:fqdn])
    create index(:platform_name_claims, [:status])

    create table(:platform_basename_mint_allowances) do
      add :parent_node, :text, null: false
      add :parent_name, :text, null: false
      add :address, :text, null: false
      add :snapshot_block_number, :bigint, null: false
      add :snapshot_total, :integer, null: false
      add :free_mints_used, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_basename_mint_allowances, [:parent_node, :address])
    create index(:platform_basename_mint_allowances, [:address])

    create table(:platform_basename_payment_credits) do
      add :parent_node, :text, null: false
      add :parent_name, :text, null: false
      add :address, :text, null: false
      add :payment_tx_hash, :text, null: false
      add :payment_chain_id, :bigint, null: false
      add :price_wei, :decimal, null: false
      add :consumed_at, :utc_datetime_usec
      add :consumed_node, :text
      add :consumed_fqdn, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_basename_payment_credits, [:payment_tx_hash, :payment_chain_id])
    create index(:platform_basename_payment_credits, [:address])

    create table(:platform_ens_subname_claims) do
      add :config_ref, :text, null: false
      add :owner_address, :text, null: false
      add :label, :text, null: false
      add :fqdn, :text, null: false
      add :reservation_status, :text, null: false, default: "reserved"
      add :mint_status, :text, null: false, default: "pending"
      add :reservation_tx_hash, :text
      add :mint_tx_hash, :text
      add :last_error_code, :text
      add :last_error_message, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_ens_subname_claims, [:config_ref])
    create index(:platform_ens_subname_claims, [:fqdn])

    create table(:platform_redeem_claims) do
      add :wallet_address, :text, null: false
      add :source_collection, :text, null: false
      add :token_id, :decimal, null: false
      add :tx_hash, :text, null: false
      add :status, :text, null: false, default: "indexed"
      add :source, :text, null: false, default: "fixture"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_redeem_claims, [:tx_hash])
    create index(:platform_redeem_claims, [:wallet_address])

    create table(:platform_import_runs) do
      add :source, :text, null: false
      add :source_database, :text, null: false
      add :notes, :text
      add :status, :text, null: false, default: "running"
      add :imported_counts, :map, null: false, default: %{}
      add :finished_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end
  end
end
