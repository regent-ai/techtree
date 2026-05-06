defmodule TechTree.NodeAccess.NodePurchaseEntitlement do
  @moduledoc false
  use TechTree.Schema

  @address_regex ~r/^0x[0-9a-f]{40}$/
  @tx_hash_regex ~r/^0x[0-9a-f]{64}$/

  schema "node_purchase_entitlements" do
    field :buyer_wallet_address, :string
    field :tx_hash, :string
    field :chain_id, :integer
    field :amount_usdc, :decimal
    field :verification_status, Ecto.Enum, values: [:verified], default: :verified
    field :listing_ref, :string
    field :bundle_ref, :string

    belongs_to :node, TechTree.Nodes.Node
    belongs_to :seller_agent, TechTree.Agents.AgentIdentity
    belongs_to :buyer_agent, TechTree.Agents.AgentIdentity
    belongs_to :buyer_human, TechTree.Accounts.HumanUser

    timestamps(updated_at: false)
  end

  def changeset(entitlement, attrs) do
    entitlement
    |> cast(attrs, [
      :node_id,
      :seller_agent_id,
      :buyer_agent_id,
      :buyer_human_id,
      :buyer_wallet_address,
      :tx_hash,
      :chain_id,
      :amount_usdc,
      :verification_status,
      :listing_ref,
      :bundle_ref
    ])
    |> validate_required([
      :node_id,
      :seller_agent_id,
      :buyer_wallet_address,
      :tx_hash,
      :chain_id,
      :amount_usdc,
      :verification_status,
      :listing_ref,
      :bundle_ref
    ])
    |> validate_number(:amount_usdc, greater_than: 0)
    |> validate_inclusion(:chain_id, [8_453])
    |> validate_format(:buyer_wallet_address, @address_regex)
    |> validate_format(:tx_hash, @tx_hash_regex)
    |> validate_format(:listing_ref, @tx_hash_regex)
    |> validate_format(:bundle_ref, @tx_hash_regex)
    |> foreign_key_constraint(:node_id)
    |> foreign_key_constraint(:seller_agent_id)
    |> foreign_key_constraint(:buyer_agent_id)
    |> foreign_key_constraint(:buyer_human_id)
    |> unique_constraint(:tx_hash)
  end
end
