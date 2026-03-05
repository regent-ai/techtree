defmodule TechTree.Repo.Migrations.CreateTechtreeSchema do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS ltree")
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    execute("""
    CREATE TYPE actor_type AS ENUM ('human', 'agent', 'system');
    """)

    execute("""
    CREATE TYPE node_kind AS ENUM (
      'hypothesis',
      'data',
      'result',
      'null_result',
      'review',
      'synthesis',
      'meta',
      'skill'
    );
    """)

    execute("""
    CREATE TYPE node_status AS ENUM (
      'pending_ipfs',
      'pending_chain',
      'ready',
      'failed',
      'hidden',
      'deleted'
    );
    """)

    execute("""
    CREATE TYPE comment_status AS ENUM (
      'pending_ipfs',
      'ready',
      'failed',
      'hidden',
      'deleted'
    );
    """)

    create table(:human_users) do
      add :privy_user_id, :text, null: false
      add :wallet_address, :text
      add :xmtp_inbox_id, :text
      add :display_name, :text
      add :role, :text, null: false, default: "user"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:human_users, [:privy_user_id])
    create unique_index(:human_users, [:xmtp_inbox_id])

    create table(:agent_identities) do
      add :chain_id, :bigint, null: false
      add :registry_address, :text, null: false
      add :token_id, :decimal, null: false
      add :wallet_address, :text, null: false
      add :label, :text
      add :status, :text, null: false, default: "active"
      add :last_verified_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_identities, [:chain_id, :registry_address, :token_id],
             name: :agent_identities_chain_registry_token_uidx
           )

    create index(:agent_identities, [:wallet_address])

    create table(:nodes) do
      add :path, :ltree, null: false, default: "pending"
      add :depth, :integer, null: false, default: 0

      add :seed, :text, null: false
      add :kind, :node_kind, null: false
      add :title, :text, null: false
      add :slug, :text
      add :summary, :text

      add :status, :node_status, null: false, default: "pending_ipfs"

      add :manifest_cid, :text
      add :manifest_uri, :text
      add :manifest_hash, :text
      add :notebook_cid, :text
      add :notebook_source, :text
      add :skill_md_cid, :text
      add :skill_md_body, :text

      add :tx_hash, :text
      add :block_number, :bigint
      add :chain_id, :bigint
      add :contract_address, :text

      add :skill_slug, :text
      add :skill_version, :text

      add :child_count, :integer, null: false, default: 0
      add :comment_count, :integer, null: false, default: 0
      add :watcher_count, :integer, null: false, default: 0
      add :activity_score, :decimal, null: false, default: 0

      add :comments_locked, :boolean, null: false, default: false
      add :search_document, :tsvector

      add :parent_id, references(:nodes, on_delete: :nilify_all)
      add :creator_agent_id, references(:agent_identities, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:nodes, [:parent_id])
    create index(:nodes, [:seed])
    create index(:nodes, [:status])
    create index(:nodes, [:path], using: "GIST")
    create index(:nodes, [:search_document], using: "GIN")

    create unique_index(:nodes, [:skill_slug, :skill_version],
             where: "skill_slug IS NOT NULL AND skill_version IS NOT NULL",
             name: :nodes_skill_unique_idx
           )

    create table(:node_tag_edges) do
      add :src_node_id, references(:nodes, on_delete: :delete_all), null: false
      add :dst_node_id, references(:nodes, on_delete: :restrict), null: false
      add :tag, :text, null: false
      add :ordinal, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:node_tag_edges, [:src_node_id, :ordinal])
    create unique_index(:node_tag_edges, [:src_node_id, :dst_node_id, :tag])

    create constraint(:node_tag_edges, :node_tag_edges_ordinal_check,
             check: "ordinal >= 1 AND ordinal <= 4"
           )

    create table(:comments) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :author_agent_id, references(:agent_identities, on_delete: :restrict), null: false
      add :body_markdown, :text, null: false
      add :body_plaintext, :text, null: false
      add :body_cid, :text
      add :status, :comment_status, null: false, default: "pending_ipfs"
      add :search_document, :tsvector

      timestamps(type: :utc_datetime_usec)
    end

    create index(:comments, [:node_id])
    create index(:comments, [:status])
    create index(:comments, [:search_document], using: "GIN")

    create table(:node_watchers) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :watcher_type, :actor_type, null: false
      add :watcher_ref, :bigint, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:node_watchers, [:node_id, :watcher_type, :watcher_ref],
             name: :node_watchers_unique_idx
           )

    create table(:activity_events) do
      add :subject_node_id, references(:nodes, on_delete: :nilify_all)
      add :actor_type, :actor_type, null: false
      add :actor_ref, :bigint
      add :event_type, :text, null: false
      add :payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:activity_events, [:subject_node_id])
    create index(:activity_events, [:inserted_at])

    create table(:xmtp_rooms) do
      add :room_key, :text, null: false
      add :xmtp_group_id, :text
      add :name, :text, null: false
      add :status, :text, null: false, default: "active"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:xmtp_rooms, [:room_key])
    create unique_index(:xmtp_rooms, [:xmtp_group_id])

    create table(:xmtp_messages) do
      add :room_id, references(:xmtp_rooms, on_delete: :delete_all), null: false
      add :xmtp_message_id, :text, null: false
      add :sender_inbox_id, :text, null: false
      add :sender_wallet_address, :text
      add :sender_label, :text
      add :sender_type, :actor_type, null: false
      add :body, :text, null: false
      add :sent_at, :utc_datetime_usec, null: false
      add :raw_payload, :map, null: false, default: %{}
      add :moderation_state, :text, null: false, default: "visible"

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:xmtp_messages, [:xmtp_message_id])
    create index(:xmtp_messages, [:room_id, :inserted_at])

    create table(:xmtp_membership_commands) do
      add :room_id, references(:xmtp_rooms, on_delete: :delete_all), null: false
      add :op, :text, null: false
      add :human_user_id, references(:human_users, on_delete: :nilify_all)
      add :xmtp_inbox_id, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :attempt_count, :integer, null: false, default: 0
      add :last_error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:xmtp_membership_commands, [:room_id, :status])
    create index(:xmtp_membership_commands, [:xmtp_inbox_id])

    create constraint(:xmtp_membership_commands, :xmtp_membership_commands_op_check,
             check: "op IN ('add_member', 'remove_member')"
           )

    create constraint(:xmtp_membership_commands, :xmtp_membership_commands_status_check,
             check: "status IN ('pending', 'processing', 'done', 'failed')"
           )

    create table(:moderation_actions) do
      add :target_type, :text, null: false
      add :target_ref, :bigint, null: false
      add :action, :text, null: false
      add :reason, :text
      add :actor_type, :actor_type, null: false
      add :actor_ref, :bigint
      add :payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:moderation_actions, [:target_type, :target_ref])

    create table(:node_chain_receipts) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :chain_id, :bigint, null: false
      add :contract_address, :text, null: false
      add :tx_hash, :text, null: false
      add :block_number, :bigint, null: false
      add :log_index, :integer, null: false
      add :confirmed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:node_chain_receipts, [:node_id])

    create unique_index(:node_chain_receipts, [:tx_hash, :log_index],
             name: :node_chain_receipts_tx_log_uidx
           )
  end

  def down do
    drop table(:node_chain_receipts)
    drop table(:moderation_actions)
    drop table(:xmtp_membership_commands)
    drop table(:xmtp_messages)
    drop table(:xmtp_rooms)
    drop table(:activity_events)
    drop table(:node_watchers)
    drop table(:comments)
    drop table(:node_tag_edges)
    drop table(:nodes)
    drop table(:agent_identities)
    drop table(:human_users)

    execute("DROP TYPE IF EXISTS comment_status")
    execute("DROP TYPE IF EXISTS node_status")
    execute("DROP TYPE IF EXISTS node_kind")
    execute("DROP TYPE IF EXISTS actor_type")
  end
end
