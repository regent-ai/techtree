defmodule TechTree.NodeAccess.NodePaidPayload do
  @moduledoc false
  use TechTree.Schema

  schema "node_paid_payloads" do
    field :status, Ecto.Enum, values: [:draft, :active, :paused, :closed], default: :draft
    field :delivery_mode, Ecto.Enum, values: [:server_verified], default: :server_verified
    field :payment_rail, Ecto.Enum, values: [:onchain], default: :onchain
    field :encrypted_payload_uri, :string
    field :encrypted_payload_cid, :string
    field :payload_hash, :string
    field :encryption_meta, :map, default: %{}
    field :access_policy, :map, default: %{}
    field :chain_id, :integer
    field :settlement_contract_address, :string
    field :usdc_token_address, :string
    field :treasury_address, :string
    field :seller_payout_address, :string
    field :price_usdc, :decimal
    field :listing_ref, :string
    field :bundle_ref, :string

    field :verified_purchase_count, :integer, virtual: true
    field :viewer_has_verified_purchase, :boolean, virtual: true, default: false

    belongs_to :node, TechTree.Nodes.Node
    belongs_to :seller_agent, TechTree.Agents.AgentIdentity

    timestamps()
  end

  def changeset(payload, attrs) do
    payload
    |> cast(attrs, [
      :node_id,
      :seller_agent_id,
      :status,
      :delivery_mode,
      :payment_rail,
      :encrypted_payload_uri,
      :encrypted_payload_cid,
      :payload_hash,
      :encryption_meta,
      :access_policy,
      :chain_id,
      :settlement_contract_address,
      :usdc_token_address,
      :treasury_address,
      :seller_payout_address,
      :price_usdc,
      :listing_ref,
      :bundle_ref
    ])
    |> validate_required([:node_id, :seller_agent_id, :status, :delivery_mode, :payment_rail])
    |> validate_location()
    |> validate_active_shape()
    |> foreign_key_constraint(:node_id)
    |> foreign_key_constraint(:seller_agent_id)
    |> unique_constraint(:node_id)
    |> unique_constraint(:listing_ref)
  end

  defp validate_location(changeset) do
    if present_text?(get_field(changeset, :encrypted_payload_uri)) or
         present_text?(get_field(changeset, :encrypted_payload_cid)) do
      changeset
    else
      add_error(changeset, :encrypted_payload_uri, "encrypted payload location is required")
    end
  end

  defp validate_active_shape(changeset) do
    case get_field(changeset, :status) do
      status when status in [:active, :paused, :closed] ->
        changeset
        |> validate_required([
          :chain_id,
          :settlement_contract_address,
          :usdc_token_address,
          :treasury_address,
          :seller_payout_address,
          :price_usdc,
          :listing_ref,
          :bundle_ref
        ])
        |> validate_number(:price_usdc, greater_than: 0)

      _ ->
        changeset
    end
  end

  defp present_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_text?(_value), do: false
end
