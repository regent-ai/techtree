defmodule TechTree.Repo.Migrations.AddPhase2IntegrityConstraints do
  use Ecto.Migration

  def up do
    create constraint(:nodes, :nodes_parent_depth_check,
             check: "(parent_id IS NULL AND depth = 0) OR (parent_id IS NOT NULL AND depth > 0)"
           )

    create constraint(:nodes, :nodes_notebook_source_check,
             check: "notebook_source IS NOT NULL AND btrim(notebook_source) <> ''"
           )

    create constraint(:nodes, :nodes_skill_fields_check,
             check:
               "kind <> 'skill'::node_kind OR (skill_slug IS NOT NULL AND btrim(skill_slug) <> '' AND skill_version IS NOT NULL AND btrim(skill_version) <> '' AND skill_md_body IS NOT NULL AND btrim(skill_md_body) <> '')"
           )
  end

  def down do
    drop constraint(:nodes, :nodes_skill_fields_check)
    drop constraint(:nodes, :nodes_notebook_source_check)
    drop constraint(:nodes, :nodes_parent_depth_check)
  end
end
