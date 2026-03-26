defmodule TechTree.Repo.Migrations.CreateNodeLineageTables do
  use Ecto.Migration

  def up do
    create table(:node_cross_chain_links) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :author_agent_id, references(:agent_identities, on_delete: :delete_all), null: false
      add :relation, :string, null: false
      add :target_chain_id, :bigint, null: false
      add :target_node_ref, :text, null: false
      add :target_node_id, references(:nodes, on_delete: :nilify_all)
      add :note, :text
      add :withdrawn_at, :utc_datetime_usec
      add :withdrawn_reason, :string

      timestamps()
    end

    create table(:node_lineage_claims) do
      add :subject_node_id, references(:nodes, on_delete: :delete_all), null: false
      add :claimant_agent_id, references(:agent_identities, on_delete: :delete_all), null: false
      add :relation, :string, null: false
      add :target_chain_id, :bigint, null: false
      add :target_node_ref, :text, null: false
      add :target_node_id, references(:nodes, on_delete: :nilify_all)
      add :note, :text
      add :withdrawn_at, :utc_datetime_usec

      timestamps()
    end

    create index(:node_cross_chain_links, [:node_id])
    create index(:node_cross_chain_links, [:author_agent_id])
    create index(:node_cross_chain_links, [:target_node_id])
    create index(:node_cross_chain_links, [:target_chain_id])

    create unique_index(:node_cross_chain_links, [:node_id],
             where: "withdrawn_at IS NULL",
             name: :node_cross_chain_links_active_node_uidx
           )

    create index(:node_lineage_claims, [:subject_node_id])
    create index(:node_lineage_claims, [:claimant_agent_id])
    create index(:node_lineage_claims, [:target_node_id])
    create index(:node_lineage_claims, [:target_chain_id])

    create unique_index(
             :node_lineage_claims,
             [
               :subject_node_id,
               :claimant_agent_id,
               :relation,
               :target_chain_id,
               :target_node_ref
             ],
             where: "withdrawn_at IS NULL",
             name: :node_lineage_claims_active_dedupe_uidx
           )

    create constraint(
             :node_cross_chain_links,
             :node_cross_chain_links_relation_check,
             check:
               "relation IN ('reproduces','fork_of','adaptation_of','promoted_from','backported_from','copy_of')"
           )

    create constraint(
             :node_cross_chain_links,
             :node_cross_chain_links_withdrawn_reason_check,
             check: "withdrawn_reason IS NULL OR withdrawn_reason IN ('replaced','cleared')"
           )

    create constraint(
             :node_lineage_claims,
             :node_lineage_claims_relation_check,
             check:
               "relation IN ('reproduces','fork_of','adaptation_of','promoted_from','backported_from','copy_of')"
           )
  end

  def down do
    drop_if_exists constraint(:node_lineage_claims, :node_lineage_claims_relation_check)

    drop_if_exists constraint(
                     :node_cross_chain_links,
                     :node_cross_chain_links_withdrawn_reason_check
                   )

    drop_if_exists constraint(:node_cross_chain_links, :node_cross_chain_links_relation_check)

    drop_if_exists index(:node_lineage_claims, [:subject_node_id])
    drop_if_exists index(:node_lineage_claims, [:claimant_agent_id])
    drop_if_exists index(:node_lineage_claims, [:target_node_id])
    drop_if_exists index(:node_lineage_claims, [:target_chain_id])
    drop_if_exists index(:node_cross_chain_links, [:node_id])
    drop_if_exists index(:node_cross_chain_links, [:author_agent_id])
    drop_if_exists index(:node_cross_chain_links, [:target_node_id])
    drop_if_exists index(:node_cross_chain_links, [:target_chain_id])

    drop_if_exists index(:node_cross_chain_links, [:node_id],
                     name: :node_cross_chain_links_active_node_uidx
                   )

    drop_if_exists index(
                     :node_lineage_claims,
                     [
                       :subject_node_id,
                       :claimant_agent_id,
                       :relation,
                       :target_chain_id,
                       :target_node_ref
                     ],
                     name: :node_lineage_claims_active_dedupe_uidx
                   )

    drop table(:node_lineage_claims)
    drop table(:node_cross_chain_links)
  end
end
