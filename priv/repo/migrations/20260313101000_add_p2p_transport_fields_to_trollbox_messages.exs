defmodule TechTree.Repo.Migrations.AddP2pTransportFieldsToChatboxMessages do
  use Ecto.Migration

  def up do
    alter table(:chatbox_messages) do
      add :room_id, :text
      add :transport_msg_id, :text
      add :transport_topic, :text
      add :origin_peer_id, :text
      add :origin_node_id, :text
      add :transport_payload, :map, null: false, default: %{}
      add :author_transport_id, :text
      add :author_display_name_snapshot, :text
      add :author_label_snapshot, :text
      add :author_wallet_address_snapshot, :text
      add :reply_to_transport_msg_id, :text
    end

    execute("UPDATE chatbox_messages SET room_id = 'global' WHERE room_id IS NULL")

    execute("""
    UPDATE chatbox_messages
    SET transport_msg_id = 'legacy:' || id::text
    WHERE transport_msg_id IS NULL
    """)

    execute("""
    UPDATE chatbox_messages
    SET transport_topic = 'regent.legacy.chatbox.global'
    WHERE transport_topic IS NULL
    """)

    alter table(:chatbox_messages) do
      modify :room_id, :text, null: false
      modify :transport_msg_id, :text, null: false
      modify :transport_topic, :text, null: false
    end

    drop constraint(:chatbox_messages, :chatbox_messages_author_ref_check)

    create unique_index(:chatbox_messages, [:transport_msg_id],
             name: :chatbox_messages_transport_msg_id_uidx
           )

    create index(:chatbox_messages, [:room_id, :inserted_at],
             name: :chatbox_messages_room_inserted_at_idx
           )

    create index(:chatbox_messages, [:reply_to_transport_msg_id],
             name: :chatbox_messages_reply_to_transport_msg_id_idx
           )

    create constraint(:chatbox_messages, :chatbox_messages_author_ref_check,
             check:
               "(author_kind = 'human' AND author_agent_id IS NULL AND (author_human_id IS NOT NULL OR author_wallet_address_snapshot IS NOT NULL)) OR " <>
                 "(author_kind = 'agent' AND author_human_id IS NULL AND (author_agent_id IS NOT NULL OR author_wallet_address_snapshot IS NOT NULL OR author_transport_id IS NOT NULL))"
           )
  end

  def down do
    drop constraint(:chatbox_messages, :chatbox_messages_author_ref_check)

    drop index(:chatbox_messages, [:reply_to_transport_msg_id],
           name: :chatbox_messages_reply_to_transport_msg_id_idx
         )

    drop index(:chatbox_messages, [:room_id, :inserted_at],
           name: :chatbox_messages_room_inserted_at_idx
         )

    drop index(:chatbox_messages, [:transport_msg_id],
           name: :chatbox_messages_transport_msg_id_uidx
         )

    alter table(:chatbox_messages) do
      remove :reply_to_transport_msg_id
      remove :author_wallet_address_snapshot
      remove :author_label_snapshot
      remove :author_display_name_snapshot
      remove :author_transport_id
      remove :transport_payload
      remove :origin_node_id
      remove :origin_peer_id
      remove :transport_topic
      remove :transport_msg_id
      remove :room_id
    end

    create constraint(:chatbox_messages, :chatbox_messages_author_ref_check,
             check:
               "(author_kind = 'human' AND author_human_id IS NOT NULL AND author_agent_id IS NULL) OR " <>
                 "(author_kind = 'agent' AND author_agent_id IS NOT NULL AND author_human_id IS NULL)"
           )
  end
end
