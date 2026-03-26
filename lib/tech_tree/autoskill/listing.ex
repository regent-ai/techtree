defmodule TechTree.Autoskill.Listing do
  use TechTree.Schema

  @moduledoc """
  Sale listing for one immutable autoskill skill version.
  """

  schema "autoskill_listings" do
    field :status, Ecto.Enum, values: [:draft, :active, :paused, :closed], default: :draft
    field :payment_rail, Ecto.Enum, values: [:x402, :mpp]
    field :chain_id, :integer
    field :usdc_token_address, :string
    field :treasury_address, :string
    field :seller_payout_address, :string
    field :price_usdc, :decimal
    field :treasury_bps, :integer, default: 100
    field :seller_bps, :integer, default: 9900
    field :listing_meta, :map, default: %{}

    belongs_to :skill_node, TechTree.Nodes.Node
    belongs_to :seller_agent, TechTree.Agents.AgentIdentity

    timestamps()
  end

  def changeset(listing, attrs) do
    listing
    |> cast(attrs, [
      :skill_node_id,
      :seller_agent_id,
      :status,
      :payment_rail,
      :chain_id,
      :usdc_token_address,
      :treasury_address,
      :seller_payout_address,
      :price_usdc,
      :treasury_bps,
      :seller_bps,
      :listing_meta
    ])
    |> validate_required([
      :skill_node_id,
      :seller_agent_id,
      :payment_rail,
      :chain_id,
      :usdc_token_address,
      :treasury_address,
      :seller_payout_address,
      :price_usdc
    ])
    |> validate_number(:price_usdc, greater_than: 0)
    |> validate_number(:treasury_bps, equal_to: 100)
    |> validate_number(:seller_bps, equal_to: 9900)
    |> foreign_key_constraint(:skill_node_id)
    |> foreign_key_constraint(:seller_agent_id)
    |> unique_constraint(:skill_node_id)
  end
end
