defmodule TechTree.Repo.Migrations.AddXmtpPresenceHeartbeats do
  use Ecto.Migration

  def change do
    create table(:xmtp_presence_heartbeats) do
      add :room_id, references(:xmtp_rooms, on_delete: :delete_all), null: false
      add :human_user_id, references(:human_users, on_delete: :delete_all), null: false
      add :xmtp_inbox_id, :text, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :evicted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:xmtp_presence_heartbeats, [:room_id, :xmtp_inbox_id],
             name: :xmtp_presence_heartbeats_room_inbox_uidx
           )

    create index(:xmtp_presence_heartbeats, [:room_id, :expires_at],
             where: "evicted_at IS NULL",
             name: :xmtp_presence_heartbeats_active_expiry_idx
           )
  end
end
