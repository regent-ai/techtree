defmodule TechTree.Platform.RedeemClaim do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{}

  schema "platform_redeem_claims" do
    field :wallet_address, :string
    field :source_collection, :string
    field :token_id, :decimal
    field :tx_hash, :string
    field :status, :string, default: "indexed"
    field :source, :string, default: "fixture"

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:wallet_address, :source_collection, :token_id, :tx_hash, :status, :source])
    |> validate_required([
      :wallet_address,
      :source_collection,
      :token_id,
      :tx_hash,
      :status,
      :source
    ])
    |> unique_constraint(:tx_hash)
  end
end
