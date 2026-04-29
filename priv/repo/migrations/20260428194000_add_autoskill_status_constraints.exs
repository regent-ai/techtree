defmodule TechTree.Repo.Migrations.AddAutoskillStatusConstraints do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE node_bundles
    ADD CONSTRAINT node_bundles_bundle_type_check
    CHECK (bundle_type IN ('skill', 'eval')) NOT VALID
    """)

    execute("""
    ALTER TABLE node_bundles
    ADD CONSTRAINT node_bundles_access_mode_check
    CHECK (access_mode IN ('public_free', 'gated_paid')) NOT VALID
    """)

    execute("""
    ALTER TABLE node_bundles
    ADD CONSTRAINT node_bundles_payment_rail_check
    CHECK (payment_rail IS NULL OR payment_rail IN ('onchain')) NOT VALID
    """)

    execute("""
    ALTER TABLE autoskill_results
    ADD CONSTRAINT autoskill_results_runtime_kind_check
    CHECK (runtime_kind IN ('local', 'molab', 'wasm', 'self_hosted')) NOT VALID
    """)

    execute("""
    ALTER TABLE autoskill_results
    ADD CONSTRAINT autoskill_results_status_check
    CHECK (status IN ('complete', 'failed')) NOT VALID
    """)

    execute("""
    ALTER TABLE autoskill_reviews
    ADD CONSTRAINT autoskill_reviews_kind_check
    CHECK (kind IN ('community', 'replicable')) NOT VALID
    """)

    execute("""
    ALTER TABLE autoskill_reviews
    ADD CONSTRAINT autoskill_reviews_runtime_kind_check
    CHECK (runtime_kind IS NULL OR runtime_kind IN ('local', 'molab', 'wasm', 'self_hosted')) NOT VALID
    """)

    execute("""
    ALTER TABLE autoskill_listings
    ADD CONSTRAINT autoskill_listings_status_check
    CHECK (status IN ('draft', 'active', 'paused', 'closed')) NOT VALID
    """)

    execute("""
    ALTER TABLE autoskill_listings
    ADD CONSTRAINT autoskill_listings_payment_rail_check
    CHECK (payment_rail IN ('onchain')) NOT VALID
    """)
  end

  def down do
    raise "hard cutover only"
  end
end
