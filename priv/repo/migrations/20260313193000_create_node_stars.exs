defmodule TechTree.Repo.Migrations.CreateNodeStars do
  use Ecto.Migration

  def change do
    create table(:node_stars) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :actor_type, :actor_type, null: false
      add :actor_ref, :bigint, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:node_stars, [:node_id, :actor_type, :actor_ref],
             name: :node_stars_unique_idx
           )
  end
end
