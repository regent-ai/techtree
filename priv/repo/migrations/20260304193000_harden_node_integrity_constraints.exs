defmodule TechTree.Repo.Migrations.HardenNodeIntegrityConstraints do
  use Ecto.Migration

  @seed_roots ["ML", "Bioscience", "Polymarket", "DeFi", "Firmware", "Skills", "Evals"]

  def up do
    create constraint(:nodes, :nodes_non_seed_parent_required_check,
             check:
               "parent_id IS NOT NULL OR seed = ANY (ARRAY['#{Enum.join(@seed_roots, "','")}'])"
           )

    drop constraint(:nodes, :nodes_skill_fields_check)

    create constraint(:nodes, :nodes_skill_fields_check,
             check:
               "(kind = 'skill'::node_kind AND skill_slug IS NOT NULL AND btrim(skill_slug) <> '' AND skill_version IS NOT NULL AND btrim(skill_version) <> '' AND skill_md_body IS NOT NULL AND btrim(skill_md_body) <> '') OR (kind <> 'skill'::node_kind AND skill_slug IS NULL AND skill_version IS NULL AND skill_md_body IS NULL)"
           )
  end

  def down do
    drop constraint(:nodes, :nodes_non_seed_parent_required_check)
    drop constraint(:nodes, :nodes_skill_fields_check)

    create constraint(:nodes, :nodes_skill_fields_check,
             check:
               "kind <> 'skill'::node_kind OR (skill_slug IS NOT NULL AND btrim(skill_slug) <> '' AND skill_version IS NOT NULL AND btrim(skill_version) <> '' AND skill_md_body IS NOT NULL AND btrim(skill_md_body) <> '')"
           )
  end
end
