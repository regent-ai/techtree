defmodule TechTree.Repo.Migrations.CreateChatboxMessageReactions do
  use Ecto.Migration

  def change do
    execute("""
    CREATE TABLE IF NOT EXISTS chatbox_messages (
      id bigserial PRIMARY KEY,
      author_kind actor_type NOT NULL,
      author_scope text NOT NULL,
      author_human_id bigint REFERENCES human_users(id) ON DELETE SET NULL,
      author_agent_id bigint REFERENCES agent_identities(id) ON DELETE SET NULL,
      client_message_id text,
      body text NOT NULL,
      reply_to_message_id bigint REFERENCES chatbox_messages(id) ON DELETE SET NULL,
      reactions jsonb NOT NULL DEFAULT '{}'::jsonb,
      moderation_state text NOT NULL DEFAULT 'visible',
      inserted_at timestamp(6) without time zone NOT NULL,
      updated_at timestamp(6) without time zone NOT NULL,
      CONSTRAINT chatbox_messages_author_kind_check
        CHECK (author_kind IN ('human', 'agent')),
      CONSTRAINT chatbox_messages_author_ref_check
        CHECK (
          (author_kind = 'human' AND author_human_id IS NOT NULL AND author_agent_id IS NULL) OR
          (author_kind = 'agent' AND author_agent_id IS NOT NULL AND author_human_id IS NULL)
        )
    )
    """)

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS chatbox_messages_author_scope_client_message_id_uidx
    ON chatbox_messages (author_scope, client_message_id)
    WHERE client_message_id IS NOT NULL
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS chatbox_messages_inserted_at_id_idx
    ON chatbox_messages (inserted_at DESC, id DESC)
    """)

    create table(:chatbox_message_reactions) do
      add :message_id, references(:chatbox_messages, on_delete: :delete_all), null: false
      add :actor_kind, :actor_type, null: false
      add :actor_ref, :integer, null: false
      add :reaction, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:chatbox_message_reactions, [:message_id])
    create index(:chatbox_message_reactions, [:actor_kind, :actor_ref])

    create unique_index(
             :chatbox_message_reactions,
             [:message_id, :actor_kind, :actor_ref, :reaction],
             name: :chatbox_message_reactions_message_actor_reaction_uidx
           )
  end
end
