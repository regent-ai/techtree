defmodule TechTree.NodeAccess.Payloads do
  @moduledoc false

  alias Decimal, as: D
  alias TechTree.Autoskill.Listing
  alias TechTree.IPFS.LighthouseClient
  alias TechTree.NodeAccess.NodePaidPayload
  alias TechTree.Nodes.Node

  @micro_usdc D.new("1000000")

  def project_payload(payload, counts_by_node_id, entitled_node_ids) do
    %{
      status: Atom.to_string(payload.status),
      delivery_mode: Atom.to_string(payload.delivery_mode),
      payment_rail: Atom.to_string(payload.payment_rail),
      chain_id: payload.chain_id,
      settlement_contract_address: payload.settlement_contract_address,
      usdc_token_address: payload.usdc_token_address,
      treasury_address: payload.treasury_address,
      seller_payout_address: payload.seller_payout_address,
      price_usdc: decimal_to_string(payload.price_usdc),
      listing_ref: payload.listing_ref,
      bundle_ref: payload.bundle_ref,
      verified_purchase_count: Map.get(counts_by_node_id, payload.node_id, 0),
      viewer_has_verified_purchase: MapSet.member?(entitled_node_ids, payload.node_id)
    }
  end

  def normalize_optional_payload_attrs(attrs) when is_map(attrs) do
    attrs
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> drop_nil_values()
  end

  def ensure_refs(attrs, %Node{} = node) do
    attrs
    |> Map.put_new("listing_ref", stable_ref("listing:#{node.id}"))
    |> Map.put_new(
      "bundle_ref",
      stable_ref(
        "bundle:#{node.id}:#{Map.get(attrs, "payload_hash") || Map.get(attrs, "encrypted_payload_cid") || Map.get(attrs, "encrypted_payload_uri")}"
      )
    )
  end

  def encode_payload_download(%NodePaidPayload{} = payload) do
    %{
      node_id: payload.node_id,
      encrypted_payload_uri: payload.encrypted_payload_uri,
      download_url:
        case payload.encrypted_payload_cid do
          cid when is_binary(cid) and cid != "" -> LighthouseClient.gateway_url(cid)
          _ -> nil
        end,
      encryption_meta: payload.encryption_meta || %{},
      access_policy: payload.access_policy || %{}
    }
  end

  def listing_settlement_contract(%Listing{chain_id: chain_id}) do
    config = Application.get_env(:tech_tree, :autoskill, [])

    case Keyword.get(config, :chains, %{}) do
      %{^chain_id => value} ->
        Map.get(
          value,
          :settlement_contract_address,
          Map.get(value, "settlement_contract_address")
        )

      chain_map when is_map(chain_map) ->
        case Map.get(chain_map, chain_id) || Map.get(chain_map, Integer.to_string(chain_id)) do
          nil ->
            nil

          value ->
            Map.get(
              value,
              :settlement_contract_address,
              Map.get(value, "settlement_contract_address")
            )
        end

      _ ->
        nil
    end
  end

  def decimal_to_string(nil), do: nil
  def decimal_to_string(%D{} = value), do: D.to_string(value)
  def decimal_to_string(value) when is_binary(value), do: value
  def decimal_to_string(value), do: to_string(value)

  def decimal_to_micro_units(nil), do: 0

  def decimal_to_micro_units(value) do
    value
    |> D.new()
    |> D.mult(@micro_usdc)
    |> D.round(0)
    |> D.to_integer()
  end

  defp stable_ref(value) when is_binary(value) do
    "0x" <> Base.encode16(:crypto.hash(:sha256, value), case: :lower)
  end

  defp drop_nil_values(map) do
    Map.reject(map, fn
      {_key, nil} -> true
      {_key, value} when is_binary(value) -> String.trim(value) == ""
      _ -> false
    end)
  end
end
