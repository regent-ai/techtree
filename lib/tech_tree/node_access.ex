defmodule TechTree.NodeAccess do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Autoskill.Listing
  alias TechTree.Autoskill.NodeBundle

  alias TechTree.NodeAccess.{
    Entitlements,
    NodePaidPayload,
    NodePurchaseEntitlement,
    Payloads,
    Verification
  }

  alias TechTree.Nodes.Node
  alias TechTree.Repo

  def attach_projection(nodes, viewer \\ %{})

  def attach_projection(%Node{} = node, viewer) do
    case attach_projection([node], viewer) do
      [projected] -> projected
      _ -> node
    end
  end

  def attach_projection(nodes, viewer) when is_list(nodes) do
    node_ids =
      nodes
      |> Enum.map(& &1.id)
      |> Enum.reject(&is_nil/1)

    payloads_by_node_id =
      NodePaidPayload
      |> where([payload], payload.node_id in ^node_ids)
      |> Repo.all()
      |> Map.new(&{&1.node_id, &1})

    counts_by_node_id =
      NodePurchaseEntitlement
      |> where([entitlement], entitlement.node_id in ^node_ids)
      |> group_by([entitlement], entitlement.node_id)
      |> select([entitlement], {entitlement.node_id, count(entitlement.id)})
      |> Repo.all()
      |> Map.new()

    viewer_wallet =
      Verification.normalize_wallet(viewer[:wallet_address] || viewer["wallet_address"])

    entitled_node_ids =
      case viewer_wallet do
        nil ->
          MapSet.new()

        wallet ->
          NodePurchaseEntitlement
          |> where(
            [entitlement],
            entitlement.node_id in ^node_ids and entitlement.buyer_wallet_address == ^wallet
          )
          |> select([entitlement], entitlement.node_id)
          |> Repo.all()
          |> MapSet.new()
      end

    Enum.map(nodes, fn node ->
      case Map.get(payloads_by_node_id, node.id) do
        nil ->
          %{node | paid_payload: nil}

        payload ->
          %{
            node
            | paid_payload:
                Payloads.project_payload(payload, counts_by_node_id, entitled_node_ids)
          }
      end
    end)
  end

  def create_paid_payload(%Node{} = node, %AgentIdentity{} = seller_agent, attrs, repo \\ Repo)
      when is_map(attrs) do
    payload_attrs =
      attrs
      |> Payloads.normalize_optional_payload_attrs()
      |> Map.put("node_id", node.id)
      |> Map.put("seller_agent_id", seller_agent.id)
      |> Payloads.ensure_refs(node)

    %NodePaidPayload{}
    |> NodePaidPayload.changeset(payload_attrs)
    |> repo.insert()
  end

  def upsert_paid_payload(%Node{} = node, %AgentIdentity{} = seller_agent, attrs, repo \\ Repo)
      when is_map(attrs) do
    payload = repo.get_by(NodePaidPayload, node_id: node.id) || %NodePaidPayload{}

    payload_attrs =
      attrs
      |> Payloads.normalize_optional_payload_attrs()
      |> Map.put("node_id", node.id)
      |> Map.put("seller_agent_id", seller_agent.id)
      |> Payloads.ensure_refs(node)

    payload
    |> NodePaidPayload.changeset(payload_attrs)
    |> repo.insert_or_update()
  end

  def sync_autoskill_bundle(
        %Node{} = node,
        %AgentIdentity{} = seller_agent,
        %NodeBundle{} = bundle
      ) do
    if bundle.access_mode == :gated_paid do
      upsert_paid_payload(node, seller_agent, %{
        "status" => "draft",
        "encrypted_payload_uri" => bundle.encrypted_bundle_uri,
        "encrypted_payload_cid" => bundle.encrypted_bundle_cid,
        "payload_hash" => bundle.bundle_hash,
        "encryption_meta" => bundle.encryption_meta || %{},
        "access_policy" => bundle.access_policy || %{}
      })
    else
      {:ok, nil}
    end
  end

  def activate_from_listing(%Listing{} = listing) do
    node = Repo.get!(Node, listing.skill_node_id)
    seller_agent = Repo.get!(AgentIdentity, listing.seller_agent_id)

    upsert_paid_payload(node, seller_agent, %{
      "status" => Atom.to_string(listing.status),
      "chain_id" => listing.chain_id,
      "settlement_contract_address" => Payloads.listing_settlement_contract(listing),
      "usdc_token_address" => listing.usdc_token_address,
      "treasury_address" => listing.treasury_address,
      "seller_payout_address" => listing.seller_payout_address,
      "price_usdc" => Payloads.decimal_to_string(listing.price_usdc),
      "access_policy" => listing.listing_meta || %{}
    })
  end

  def verify_purchase_for_agent(node_id, %AgentIdentity{} = agent, tx_hash) do
    verify_purchase(node_id, tx_hash, %{
      wallet_address: agent.wallet_address,
      buyer_agent_id: agent.id
    })
  end

  def verify_purchase(node_id, tx_hash, buyer_ctx \\ %{}) do
    with {:ok, payload, node} <- fetch_active_payload(node_id),
         {:ok, normalized_tx_hash} <- Verification.normalize_tx_hash(tx_hash),
         {:ok, buyer_wallet} <- Verification.buyer_wallet_from_context(buyer_ctx),
         {:ok, verified} <-
           Verification.verify_settlement_tx(payload, normalized_tx_hash, buyer_wallet),
         attrs <- Verification.entitlement_attrs(node, payload, verified, buyer_ctx),
         {:ok, entitlement} <- Entitlements.persist_entitlement(attrs) do
      {:ok, %{payload: payload, entitlement: entitlement}}
    end
  end

  def fetch_payload_for_agent(node_id, %AgentIdentity{} = agent) do
    with {:ok, payload, _node} <- fetch_active_payload(node_id),
         :ok <- Entitlements.authorize_payload_access(payload, agent.wallet_address, agent.id) do
      {:ok, Payloads.encode_payload_download(payload)}
    end
  end

  def seller_summary_for_wallet(wallet_address) do
    wallet = Verification.normalize_wallet(wallet_address)

    seller_agent_ids =
      AgentIdentity
      |> where([agent], agent.wallet_address == ^wallet)
      |> select([agent], agent.id)
      |> Repo.all()

    Entitlements.summarize_sales(seller_agent_ids)
  end

  def seller_summary_for_agent(agent_id) when is_integer(agent_id) do
    Entitlements.summarize_sales([agent_id])
  end

  defp fetch_active_payload(node_id) do
    normalized_node_id =
      case node_id do
        value when is_integer(value) and value > 0 ->
          {:ok, value}

        value when is_binary(value) ->
          case Integer.parse(String.trim(value)) do
            {parsed, ""} when parsed > 0 -> {:ok, parsed}
            _ -> {:error, :invalid_node_id}
          end

        _ ->
          {:error, :invalid_node_id}
      end

    with {:ok, normalized_node_id} <- normalized_node_id,
         %Node{} = node <- Repo.get(Node, normalized_node_id) || {:error, :node_not_found},
         %NodePaidPayload{} = payload <-
           Repo.get_by(NodePaidPayload, node_id: normalized_node_id) ||
             {:error, :paid_payload_not_found},
         true <- payload.status == :active || {:error, :paid_payload_not_active} do
      {:ok, payload, node}
    end
  end
end
