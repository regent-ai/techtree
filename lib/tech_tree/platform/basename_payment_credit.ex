defmodule TechTree.Platform.BasenamePaymentCredit do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{}

  schema "platform_basename_payment_credits" do
    field :parent_node, :string
    field :parent_name, :string
    field :address, :string
    field :payment_tx_hash, :string
    field :payment_chain_id, :integer
    field :price_wei, :decimal
    field :consumed_at, :utc_datetime_usec
    field :consumed_node, :string
    field :consumed_fqdn, :string

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :parent_node,
      :parent_name,
      :address,
      :payment_tx_hash,
      :payment_chain_id,
      :price_wei,
      :consumed_at,
      :consumed_node,
      :consumed_fqdn
    ])
    |> validate_required([
      :parent_node,
      :parent_name,
      :address,
      :payment_tx_hash,
      :payment_chain_id,
      :price_wei
    ])
    |> unique_constraint([:payment_tx_hash, :payment_chain_id])
  end
end
