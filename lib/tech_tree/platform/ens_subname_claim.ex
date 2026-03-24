defmodule TechTree.Platform.EnsSubnameClaim do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{}

  schema "platform_ens_subname_claims" do
    field :config_ref, :string
    field :owner_address, :string
    field :label, :string
    field :fqdn, :string
    field :reservation_status, :string, default: "reserved"
    field :mint_status, :string, default: "pending"
    field :reservation_tx_hash, :string
    field :mint_tx_hash, :string
    field :last_error_code, :string
    field :last_error_message, :string

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :config_ref,
      :owner_address,
      :label,
      :fqdn,
      :reservation_status,
      :mint_status,
      :reservation_tx_hash,
      :mint_tx_hash,
      :last_error_code,
      :last_error_message
    ])
    |> validate_required([
      :config_ref,
      :owner_address,
      :label,
      :fqdn,
      :reservation_status,
      :mint_status
    ])
    |> unique_constraint(:config_ref)
  end
end
