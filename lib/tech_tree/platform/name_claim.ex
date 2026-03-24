defmodule TechTree.Platform.NameClaim do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{}

  schema "platform_name_claims" do
    field :label, :string
    field :fqdn, :string
    field :owner_address, :string
    field :status, :string, default: "claimed"
    field :source, :string, default: "fixture"

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(name_claim, attrs) do
    name_claim
    |> cast(attrs, [:label, :fqdn, :owner_address, :status, :source])
    |> validate_required([:label, :fqdn, :status, :source])
    |> unique_constraint(:fqdn)
  end
end
