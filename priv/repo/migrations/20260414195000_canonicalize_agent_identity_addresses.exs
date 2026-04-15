defmodule TechTree.Repo.Migrations.CanonicalizeAgentIdentityAddresses do
  use Ecto.Migration

  def up do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM agent_identities
        GROUP BY chain_id, lower(registry_address), token_id
        HAVING count(*) > 1
      ) THEN
        RAISE EXCEPTION
          'case-colliding agent identities exist; resolve duplicate chain_id + lower(registry_address) + token_id rows before migrating';
      END IF;
    END
    $$;
    """)

    execute("""
    UPDATE agent_identities
    SET
      registry_address = lower(registry_address),
      wallet_address = lower(wallet_address)
    WHERE
      registry_address <> lower(registry_address)
      OR wallet_address <> lower(wallet_address);
    """)

    drop_if_exists(
      index(:agent_identities, [:chain_id, :registry_address, :token_id],
        name: :agent_identities_chain_registry_token_uidx
      )
    )

    execute("""
    CREATE UNIQUE INDEX agent_identities_chain_registry_token_uidx_ci
    ON agent_identities (chain_id, lower(registry_address), token_id);
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS agent_identities_chain_registry_token_uidx_ci")

    create unique_index(:agent_identities, [:chain_id, :registry_address, :token_id],
             name: :agent_identities_chain_registry_token_uidx
           )
  end
end
