defmodule TechTree.Repo.Migrations.AddNodePurchaseEntitlementConstraints do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE node_purchase_entitlements
    ADD CONSTRAINT node_purchase_entitlements_amount_usdc_positive
    CHECK (amount_usdc > 0) NOT VALID
    """)

    execute("""
    ALTER TABLE node_purchase_entitlements
    ADD CONSTRAINT node_purchase_entitlements_chain_id_supported
    CHECK (chain_id IN (84532, 8453)) NOT VALID
    """)

    execute("""
    ALTER TABLE node_purchase_entitlements
    ADD CONSTRAINT node_purchase_entitlements_tx_hash_shape
    CHECK (tx_hash ~ '^0x[0-9a-f]{64}$') NOT VALID
    """)

    execute("""
    ALTER TABLE node_purchase_entitlements
    ADD CONSTRAINT node_purchase_entitlements_buyer_wallet_shape
    CHECK (buyer_wallet_address ~ '^0x[0-9a-f]{40}$') NOT VALID
    """)

    execute("""
    ALTER TABLE node_purchase_entitlements
    ADD CONSTRAINT node_purchase_entitlements_listing_ref_shape
    CHECK (listing_ref ~ '^0x[0-9a-f]{64}$') NOT VALID
    """)

    execute("""
    ALTER TABLE node_purchase_entitlements
    ADD CONSTRAINT node_purchase_entitlements_bundle_ref_shape
    CHECK (bundle_ref ~ '^0x[0-9a-f]{64}$') NOT VALID
    """)
  end

  def down do
    raise "hard cutover only"
  end
end
