defmodule TechTree.Repo.Migrations.AddCommentIdempotencyKey do
  use Ecto.Migration

  def up do
    alter table(:comments) do
      add :idempotency_key, :text
    end

    create unique_index(:comments, [:author_agent_id, :idempotency_key],
             where: "idempotency_key IS NOT NULL",
             name: :comments_author_idempotency_uidx
           )
  end

  def down do
    drop_if_exists index(:comments, [:author_agent_id, :idempotency_key],
                     name: :comments_author_idempotency_uidx
                   )

    alter table(:comments) do
      remove :idempotency_key
    end
  end
end
