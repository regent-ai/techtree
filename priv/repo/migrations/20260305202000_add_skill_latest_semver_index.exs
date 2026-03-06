defmodule TechTree.Repo.Migrations.AddSkillLatestSemverIndex do
  use Ecto.Migration

  def up do
    execute("""
    CREATE INDEX nodes_skill_latest_semver_idx
    ON nodes (
      skill_slug,
      (split_part(skill_version, '.', 1)::integer) DESC,
      (split_part(skill_version, '.', 2)::integer) DESC,
      (split_part(skill_version, '.', 3)::integer) DESC,
      inserted_at DESC
    )
    WHERE kind = 'skill'::node_kind
      AND status = 'anchored'::node_status
      AND skill_slug IS NOT NULL
      AND skill_version ~ '^[0-9]+\\.[0-9]+\\.[0-9]+$'
      AND skill_md_body IS NOT NULL
      AND btrim(skill_md_body) <> ''
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS nodes_skill_latest_semver_idx")
  end
end