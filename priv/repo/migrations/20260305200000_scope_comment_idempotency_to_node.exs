defmodule TechTree.Repo.Migrations.ScopeCommentIdempotencyToNode do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    drop_if_exists index(:comments, [:author_agent_id, :idempotency_key],
                     name: :comments_author_idempotency_uidx,
                     concurrently: true
                   )

    create unique_index(:comments, [:author_agent_id, :node_id, :idempotency_key],
             where: "idempotency_key IS NOT NULL",
             name: :comments_author_idempotency_uidx,
             concurrently: true
           )
  end

  def down do
    drop_if_exists index(:comments, [:author_agent_id, :node_id, :idempotency_key],
                     name: :comments_author_idempotency_uidx,
                     concurrently: true
                   )

    create unique_index(:comments, [:author_agent_id, :idempotency_key],
             where: "idempotency_key IS NOT NULL",
             name: :comments_author_idempotency_uidx,
             concurrently: true
           )
  end
end
