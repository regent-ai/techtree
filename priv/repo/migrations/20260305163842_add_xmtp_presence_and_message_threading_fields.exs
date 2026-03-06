defmodule TechTree.Repo.Migrations.AddXmtpPresenceAndMessageThreadingFields do
  use Ecto.Migration

  def change do
    alter table(:xmtp_rooms) do
      add :presence_ttl_seconds, :integer, null: false, default: 120
    end

    create constraint(:xmtp_rooms, :xmtp_rooms_presence_ttl_seconds_check,
             check: "presence_ttl_seconds >= 15 AND presence_ttl_seconds <= 3600"
           )

    alter table(:xmtp_messages) do
      add :reply_to_message_id, references(:xmtp_messages, on_delete: :nilify_all)
      add :reactions, :map, null: false, default: %{}
    end

    create index(:xmtp_messages, [:reply_to_message_id])
  end
end
