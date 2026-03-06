defmodule TechTree.Repo.Migrations.CutoverArtifactLifecycle do
  use Ecto.Migration

  def up do
    alter table(:nodes) do
      add :publish_idempotency_key, :text
    end

    execute("""
    UPDATE nodes
    SET publish_idempotency_key = COALESCE(
      NULLIF(publish_idempotency_key, ''),
      'node:' || id::text || ':' || COALESCE(NULLIF(manifest_hash, ''), md5(id::text || ':' || COALESCE(manifest_uri, '')))
    )
    """)

    execute("ALTER TABLE nodes ALTER COLUMN publish_idempotency_key SET NOT NULL")

    create unique_index(:nodes, [:publish_idempotency_key],
             name: :nodes_publish_idempotency_key_uidx
           )

    create table(:node_publish_attempts) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :idempotency_key, :text, null: false
      add :manifest_uri, :text, null: false
      add :manifest_hash, :text, null: false
      add :tx_hash, :text
      add :status, :text, null: false, default: "pinned"
      add :attempt_count, :integer, null: false, default: 0
      add :last_error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:node_publish_attempts, [:node_id])
    create unique_index(:node_publish_attempts, [:idempotency_key])

    execute("ALTER TYPE node_status RENAME TO node_status_old")

    execute("""
    CREATE TYPE node_status AS ENUM (
      'pinned',
      'anchored',
      'failed_anchor',
      'hidden',
      'deleted'
    )
    """)

    execute("""
    ALTER TABLE nodes
      ALTER COLUMN status DROP DEFAULT,
      ALTER COLUMN status TYPE node_status
      USING (
        CASE status::text
          WHEN 'pending_ipfs' THEN 'pinned'
          WHEN 'pending_chain' THEN 'pinned'
          WHEN 'ready' THEN 'anchored'
          WHEN 'failed' THEN 'failed_anchor'
          WHEN 'hidden' THEN 'hidden'
          WHEN 'deleted' THEN 'deleted'
        END
      )::node_status,
      ALTER COLUMN status SET DEFAULT 'pinned'
    """)

    execute("DROP TYPE node_status_old")

    execute("ALTER TYPE comment_status RENAME TO comment_status_old")

    execute("""
    CREATE TYPE comment_status AS ENUM (
      'ready',
      'hidden',
      'deleted'
    )
    """)

    execute("""
    ALTER TABLE comments
      ALTER COLUMN status DROP DEFAULT,
      ALTER COLUMN status TYPE comment_status
      USING (
        CASE status::text
          WHEN 'pending_ipfs' THEN 'ready'
          WHEN 'ready' THEN 'ready'
          WHEN 'failed' THEN 'ready'
          WHEN 'hidden' THEN 'hidden'
          WHEN 'deleted' THEN 'deleted'
        END
      )::comment_status,
      ALTER COLUMN status SET DEFAULT 'ready'
    """)

    alter table(:comments) do
      remove :body_cid
    end

    execute("DROP TYPE comment_status_old")

    execute("""
    INSERT INTO node_publish_attempts (
      node_id,
      idempotency_key,
      manifest_uri,
      manifest_hash,
      tx_hash,
      status,
      attempt_count,
      inserted_at,
      updated_at
    )
    SELECT
      n.id,
      n.publish_idempotency_key,
      n.manifest_uri,
      n.manifest_hash,
      n.tx_hash,
      CASE n.status
        WHEN 'anchored'::node_status THEN 'anchored'
        WHEN 'failed_anchor'::node_status THEN 'failed_anchor'
        ELSE 'pinned'
      END,
      CASE
        WHEN n.tx_hash IS NULL OR n.tx_hash = '' THEN 0
        ELSE 1
      END,
      now(),
      now()
    FROM nodes n
    WHERE n.manifest_uri IS NOT NULL
      AND n.manifest_uri <> ''
      AND n.manifest_hash IS NOT NULL
      AND n.manifest_hash <> ''
    ON CONFLICT (idempotency_key) DO NOTHING
    """)
  end

  def down do
    execute("ALTER TYPE comment_status RENAME TO comment_status_new")

    execute("""
    CREATE TYPE comment_status AS ENUM (
      'pending_ipfs',
      'ready',
      'failed',
      'hidden',
      'deleted'
    )
    """)

    execute("""
    ALTER TABLE comments
      ALTER COLUMN status DROP DEFAULT,
      ALTER COLUMN status TYPE comment_status
      USING (
        CASE status::text
          WHEN 'ready' THEN 'ready'
          WHEN 'hidden' THEN 'hidden'
          WHEN 'deleted' THEN 'deleted'
        END
      )::comment_status,
      ALTER COLUMN status SET DEFAULT 'pending_ipfs'
    """)

    alter table(:comments) do
      add :body_cid, :text
    end

    execute("DROP TYPE comment_status_new")

    execute("ALTER TYPE node_status RENAME TO node_status_new")

    execute("""
    CREATE TYPE node_status AS ENUM (
      'pending_ipfs',
      'pending_chain',
      'ready',
      'failed',
      'hidden',
      'deleted'
    )
    """)

    execute("""
    ALTER TABLE nodes
      ALTER COLUMN status DROP DEFAULT,
      ALTER COLUMN status TYPE node_status
      USING (
        CASE status::text
          WHEN 'pinned' THEN 'pending_chain'
          WHEN 'anchored' THEN 'ready'
          WHEN 'failed_anchor' THEN 'failed'
          WHEN 'hidden' THEN 'hidden'
          WHEN 'deleted' THEN 'deleted'
        END
      )::node_status,
      ALTER COLUMN status SET DEFAULT 'pending_ipfs'
    """)

    execute("DROP TYPE node_status_new")

    drop table(:node_publish_attempts)

    drop_if_exists index(:nodes, [:publish_idempotency_key],
                     name: :nodes_publish_idempotency_key_uidx
                   )

    alter table(:nodes) do
      remove :publish_idempotency_key
    end
  end
end
