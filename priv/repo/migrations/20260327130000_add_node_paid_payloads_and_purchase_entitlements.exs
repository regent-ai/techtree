defmodule TechTree.Repo.Migrations.AddNodePaidPayloadsAndPurchaseEntitlements do
  use Ecto.Migration

  def change do
    execute(
      "CREATE TYPE node_paid_payload_status AS ENUM ('draft', 'active', 'paused', 'closed')"
    )

    execute("CREATE TYPE node_paid_payload_delivery_mode AS ENUM ('server_verified')")
    execute("CREATE TYPE node_paid_payload_payment_rail AS ENUM ('onchain')")
    execute("CREATE TYPE node_purchase_verification_status AS ENUM ('verified')")

    create table(:node_paid_payloads) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :seller_agent_id, references(:agent_identities, on_delete: :delete_all), null: false
      add :status, :node_paid_payload_status, null: false, default: "draft"

      add :delivery_mode, :node_paid_payload_delivery_mode,
        null: false,
        default: "server_verified"

      add :payment_rail, :node_paid_payload_payment_rail, null: false, default: "onchain"
      add :encrypted_payload_uri, :text
      add :encrypted_payload_cid, :text
      add :payload_hash, :text
      add :encryption_meta, :map, null: false, default: %{}
      add :access_policy, :map, null: false, default: %{}
      add :chain_id, :integer
      add :settlement_contract_address, :text
      add :usdc_token_address, :text
      add :treasury_address, :text
      add :seller_payout_address, :text
      add :price_usdc, :decimal, precision: 30, scale: 6
      add :listing_ref, :text
      add :bundle_ref, :text

      timestamps()
    end

    create unique_index(:node_paid_payloads, [:node_id])
    create unique_index(:node_paid_payloads, [:listing_ref], where: "listing_ref IS NOT NULL")

    create table(:node_purchase_entitlements) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :seller_agent_id, references(:agent_identities, on_delete: :delete_all), null: false
      add :buyer_agent_id, references(:agent_identities, on_delete: :nilify_all)
      add :buyer_human_id, references(:human_users, on_delete: :nilify_all)
      add :buyer_wallet_address, :text, null: false
      add :tx_hash, :text, null: false
      add :chain_id, :integer, null: false
      add :amount_usdc, :decimal, precision: 30, scale: 6, null: false

      add :verification_status, :node_purchase_verification_status,
        null: false,
        default: "verified"

      add :listing_ref, :text, null: false
      add :bundle_ref, :text, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:node_purchase_entitlements, [:tx_hash])
    create index(:node_purchase_entitlements, [:node_id])
    create index(:node_purchase_entitlements, [:seller_agent_id])
    create index(:node_purchase_entitlements, [:buyer_wallet_address])
  end
end
