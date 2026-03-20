defmodule TechTree.Repo.Migrations.RemoveXmtpSurfaces do
  use Ecto.Migration

  def up do
    drop_if_exists table(:xmtp_presence_heartbeats)
    drop_if_exists table(:xmtp_membership_commands)
    drop_if_exists table(:xmtp_messages)
    drop_if_exists table(:xmtp_rooms)
    drop_if_exists table(:platform_xmtp_conversations)

    drop_if_exists index(:human_users, [:xmtp_inbox_id])

    alter table(:human_users) do
      remove_if_exists :xmtp_inbox_id, :text
    end

    alter table(:platform_agents) do
      remove_if_exists :xmtp_inbox_id, :text
    end
  end

  def down do
    raise "irreversible migration"
  end
end
