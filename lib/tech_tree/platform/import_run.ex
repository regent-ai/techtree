defmodule TechTree.Platform.ImportRun do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{}

  schema "platform_import_runs" do
    field :source, :string
    field :source_database, :string
    field :notes, :string
    field :status, :string, default: "running"
    field :imported_counts, :map, default: %{}
    field :finished_at, :utc_datetime_usec

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:source, :source_database, :notes, :status, :imported_counts, :finished_at])
    |> validate_required([:source, :source_database, :status])
  end
end
