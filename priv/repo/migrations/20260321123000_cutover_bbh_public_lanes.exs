defmodule TechTree.Repo.Migrations.CutoverBbhPublicLanes do
  use Ecto.Migration

  def up do
    alter table(:bbh_capsules) do
      add :publication_artifact_id, :text
      add :publication_review_id, :text
      add :published_at, :utc_datetime_usec
    end

    create index(:bbh_capsules, [:publication_artifact_id])
    create index(:bbh_capsules, [:publication_review_id])
    create index(:bbh_capsules, [:published_at])

    execute("UPDATE bbh_capsules SET split = 'climb' WHERE split = 'train'")
    execute("UPDATE bbh_assignments SET split = 'climb' WHERE split = 'train'")
    execute("UPDATE bbh_runs SET split = 'climb' WHERE split = 'train'")

    execute("UPDATE bbh_capsules SET split = 'draft' WHERE split = 'holdout'")
    execute("UPDATE bbh_assignments SET split = 'draft' WHERE split = 'holdout'")
    execute("UPDATE bbh_runs SET split = 'draft' WHERE split = 'holdout'")
  end

  def down do
    execute("UPDATE bbh_runs SET split = 'holdout' WHERE split = 'draft'")
    execute("UPDATE bbh_assignments SET split = 'holdout' WHERE split = 'draft'")
    execute("UPDATE bbh_capsules SET split = 'holdout' WHERE split = 'draft'")

    execute("UPDATE bbh_runs SET split = 'train' WHERE split = 'climb'")
    execute("UPDATE bbh_assignments SET split = 'train' WHERE split = 'climb'")
    execute("UPDATE bbh_capsules SET split = 'train' WHERE split = 'climb'")

    drop_if_exists index(:bbh_capsules, [:published_at])
    drop_if_exists index(:bbh_capsules, [:publication_review_id])
    drop_if_exists index(:bbh_capsules, [:publication_artifact_id])

    alter table(:bbh_capsules) do
      remove :published_at
      remove :publication_review_id
      remove :publication_artifact_id
    end
  end
end
