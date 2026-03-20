defmodule TechTree.Repo.Migrations.CreateTrollboxMessageReactions do
  use Ecto.Migration

  def change do
    create table(:trollbox_message_reactions) do
      add :message_id, references(:trollbox_messages, on_delete: :delete_all), null: false
      add :actor_kind, :actor_type, null: false
      add :actor_ref, :integer, null: false
      add :reaction, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:trollbox_message_reactions, [:message_id])
    create index(:trollbox_message_reactions, [:actor_kind, :actor_ref])

    create unique_index(
             :trollbox_message_reactions,
             [:message_id, :actor_kind, :actor_ref, :reaction],
             name: :trollbox_message_reactions_message_actor_reaction_uidx
           )
  end
end
