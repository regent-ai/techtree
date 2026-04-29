defmodule TechTree.Repo.Migrations.AllowPublishAttemptsBeforePinning do
  use Ecto.Migration

  def up do
    alter table(:node_publish_attempts) do
      modify :manifest_uri, :text, null: true
      modify :manifest_hash, :text, null: true
    end
  end

  def down do
    raise "hard cutover only"
  end
end
