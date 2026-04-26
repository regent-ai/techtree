defmodule TechTree.Repo.Migrations.HardCutXmtpRoomsToSharedManager do
  use Ecto.Migration

  def up do
    alter table(:xmtp_rooms) do
      modify :name, :text, null: true
      add :conversation_id, :text
      add :agent_wallet_address, :text
      add :agent_inbox_id, :text
      add :capacity, :integer, null: false, default: 200
      add :room_name, :text
      add :description, :text
      add :app_data, :text
      add :created_at_ns, :bigint
      add :last_activity_ns, :bigint
      add :snapshot, :map, null: false, default: %{}
    end

    create unique_index(:xmtp_rooms, [:conversation_id])

    create table(:xmtp_room_memberships) do
      add :room_id, references(:xmtp_rooms, on_delete: :delete_all), null: false
      add :wallet_address, :text, null: false
      add :inbox_id, :text, null: false
      add :principal_kind, :text, null: false, default: "human"
      add :display_name, :text
      add :membership_state, :text, null: false, default: "joined"
      add :last_seen_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:xmtp_room_memberships, [:room_id, :wallet_address])
    create unique_index(:xmtp_room_memberships, [:room_id, :inbox_id])
    create index(:xmtp_room_memberships, [:membership_state])

    create table(:xmtp_message_logs) do
      add :room_id, references(:xmtp_rooms, on_delete: :delete_all), null: false
      add :xmtp_message_id, :text, null: false
      add :conversation_id, :text, null: false
      add :sender_inbox_id, :text, null: false
      add :sender_wallet, :text
      add :sender_kind, :text
      add :sender_label, :text
      add :body, :text, null: false
      add :sent_at, :utc_datetime_usec, null: false
      add :website_visibility_state, :text, null: false, default: "visible"
      add :moderator_wallet, :text
      add :moderated_at, :utc_datetime_usec
      add :message_snapshot, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:xmtp_message_logs, [:xmtp_message_id])
    create index(:xmtp_message_logs, [:room_id, :sent_at])
    create index(:xmtp_message_logs, [:website_visibility_state])
  end

  def down do
    raise "hard cut migration is not reversible"
  end
end
