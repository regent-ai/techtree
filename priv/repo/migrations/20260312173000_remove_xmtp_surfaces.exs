defmodule TechTree.Repo.Migrations.RemoveXmtpSurfaces do
  use Ecto.Migration

  def up do
    drop_if_exists table(:platform_xmtp_conversations)
  end

  def down do
    raise "irreversible migration"
  end
end
