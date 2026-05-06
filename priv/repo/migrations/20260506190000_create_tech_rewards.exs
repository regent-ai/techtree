defmodule TechTree.Repo.Migrations.CreateTechRewards do
  use Ecto.Migration

  def up do
    create table(:tech_leaderboards, primary_key: false) do
      add :leaderboard_id, :text, primary_key: true
      add :created_by_agent_id, references(:agent_identities, on_delete: :nilify_all)
      add :kind, :text, null: false
      add :title, :text, null: false
      add :weight_bps, :integer, null: false
      add :starts_epoch, :bigint
      add :ends_epoch, :bigint
      add :config_hash, :text, null: false
      add :uri, :text, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tech_leaderboards, [:active])

    create table(:tech_reward_epochs, primary_key: false) do
      add :epoch, :bigint, primary_key: true
      add :status, :text, null: false, default: "planned"
      add :starts_at, :utc_datetime_usec
      add :ends_at, :utc_datetime_usec
      add :total_emission_amount, :text, null: false, default: "0"
      add :science_budget_amount, :text, null: false, default: "0"
      add :input_budget_amount, :text, null: false, default: "0"

      timestamps(type: :utc_datetime_usec)
    end

    create table(:tech_reward_manifests, primary_key: false) do
      add :manifest_id, :text, primary_key: true

      add :epoch,
          references(:tech_reward_epochs,
            column: :epoch,
            type: :bigint,
            on_delete: :restrict
          ),
          null: false

      add :lane, :text, null: false
      add :merkle_root, :text, null: false
      add :manifest_hash, :text, null: false
      add :total_allocated_amount, :text, null: false
      add :allocation_count, :integer, null: false, default: 0
      add :policy_version, :text, null: false
      add :leaderboard_ids, {:array, :text}, null: false, default: []
      add :reputation_filter_version, :text, null: false
      add :dust_policy, :map, null: false, default: %{}
      add :challenge_ends_at, :bigint
      add :status, :text, null: false, default: "prepared"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tech_reward_manifests, [:epoch, :lane])

    create table(:tech_reward_allocations, primary_key: false) do
      add :allocation_id, :text, primary_key: true

      add :manifest_id,
          references(:tech_reward_manifests,
            column: :manifest_id,
            type: :text,
            on_delete: :delete_all
          ),
          null: false

      add :epoch, :bigint, null: false
      add :lane, :text, null: false
      add :agent_id, :text, null: false
      add :wallet_address, :text
      add :amount, :text, null: false
      add :allocation_ref, :text, null: false
      add :proof, {:array, :text}, null: false, default: []
      add :rank, :integer, null: false
      add :score, :decimal
      add :leaderboard_id, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tech_reward_allocations, [:manifest_id, :agent_id])
    create index(:tech_reward_allocations, [:epoch, :lane, :agent_id])

    create table(:tech_withdrawals, primary_key: false) do
      add :withdrawal_id, :text, primary_key: true
      add :agent_identity_id, references(:agent_identities, on_delete: :nilify_all)
      add :agent_id, :text, null: false
      add :amount, :text, null: false
      add :tech_recipient, :text, null: false
      add :regent_recipient, :text, null: false
      add :min_regent_out, :text, null: false
      add :deadline, :bigint, null: false
      add :status, :text, null: false, default: "prepared"
      add :transaction, :map, null: false, default: %{}
      add :tx_hash, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tech_withdrawals, [:agent_identity_id])
    create index(:tech_withdrawals, [:agent_id])

    create_constraints()
  end

  def down do
    raise "hard cutover only"
  end

  defp create_constraints do
    amount_check = "VALUE ~ '^[0-9]+$'"
    bytes32_check = "VALUE ~ '^0x[0-9a-fA-F]{64}$'"
    address_check = "VALUE ~ '^0x[0-9a-fA-F]{40}$'"

    create constraint(:tech_leaderboards, :tech_leaderboards_weight_bps_check,
             check: "weight_bps >= 0 AND weight_bps <= 10000"
           )

    create constraint(:tech_leaderboards, :tech_leaderboards_config_hash_check,
             check: String.replace(bytes32_check, "VALUE", "config_hash")
           )

    for {table, field} <- [
          {:tech_reward_epochs, :total_emission_amount},
          {:tech_reward_epochs, :science_budget_amount},
          {:tech_reward_epochs, :input_budget_amount},
          {:tech_reward_manifests, :total_allocated_amount},
          {:tech_reward_allocations, :amount},
          {:tech_withdrawals, :amount},
          {:tech_withdrawals, :min_regent_out}
        ] do
      create constraint(table, :"#{table}_#{field}_check",
               check: String.replace(amount_check, "VALUE", Atom.to_string(field))
             )
    end

    create constraint(:tech_reward_epochs, :tech_reward_epochs_status_check,
             check: "status IN ('planned', 'open', 'sealed', 'posted')"
           )

    create constraint(:tech_reward_manifests, :tech_reward_manifests_lane_check,
             check: "lane IN ('science', 'usdc_input')"
           )

    create constraint(:tech_reward_manifests, :tech_reward_manifests_status_check,
             check: "status IN ('prepared', 'posted', 'retired')"
           )

    create constraint(:tech_reward_allocations, :tech_reward_allocations_lane_check,
             check: "lane IN ('science', 'usdc_input')"
           )

    for {table, field} <- [
          {:tech_reward_manifests, :merkle_root},
          {:tech_reward_manifests, :manifest_hash},
          {:tech_reward_allocations, :allocation_ref}
        ] do
      create constraint(table, :"#{table}_#{field}_check",
               check: String.replace(bytes32_check, "VALUE", Atom.to_string(field))
             )
    end

    create constraint(:tech_withdrawals, :tech_withdrawals_status_check,
             check: "status IN ('prepared', 'submitted', 'confirmed', 'failed')"
           )

    create constraint(:tech_withdrawals, :tech_withdrawals_tech_recipient_check,
             check: String.replace(address_check, "VALUE", "tech_recipient")
           )

    create constraint(:tech_withdrawals, :tech_withdrawals_regent_recipient_check,
             check: String.replace(address_check, "VALUE", "regent_recipient")
           )
  end
end
