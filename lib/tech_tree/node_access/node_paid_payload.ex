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
    |> validate_encrypted_payload_uri()
    |> validate_payload_hash()
    |> validate_wallet_or_contract_addresses()
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

  defp validate_encrypted_payload_uri(changeset) do
    case get_field(changeset, :encrypted_payload_uri) do
      value when is_binary(value) ->
        if String.starts_with?(String.trim(value), "ipfs://") do
          changeset
        else
          add_error(changeset, :encrypted_payload_uri, "must use ipfs://")
        end

      _ ->
        changeset
    end
  end

  defp validate_payload_hash(changeset) do
    case get_field(changeset, :payload_hash) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          add_error(changeset, :payload_hash, "must be present")
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  defp validate_wallet_or_contract_addresses(changeset) do
    [:settlement_contract_address, :usdc_token_address, :treasury_address, :seller_payout_address]
    |> Enum.reduce(changeset, fn field, acc ->
      case get_field(acc, field) do
        value when is_binary(value) ->
          if valid_evm_address?(value) do
            acc
          else
            add_error(acc, field, "must be an EVM address")
          end

        _ ->
          acc
      end
    end)
  end

  defp valid_evm_address?(value) when is_binary(value) do
    String.match?(String.trim(value), ~r/^0x[0-9a-fA-F]{40}$/)
  end

  defp present_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_text?(_value), do: false
end
