defmodule TechTree.NodeAccessTest do
  use TechTree.DataCase, async: true

  alias Decimal, as: D
  alias TechTree.Agents.AgentIdentity
  alias TechTree.NodeAccess
  alias TechTree.NodeAccess.NodePurchaseEntitlement
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  test "attach_projection exposes purchase counts and viewer entitlement" do
    %{seller: seller, buyer: buyer, node: node, payload: payload} = paid_payload_fixture!()

    Repo.insert!(%NodePurchaseEntitlement{
      node_id: node.id,
      seller_agent_id: seller.id,
      buyer_agent_id: buyer.id,
      buyer_wallet_address: buyer.wallet_address,
      tx_hash: "0x" <> String.duplicate("a", 64),
      chain_id: payload.chain_id,
      amount_usdc: D.new("25.000000"),
      verification_status: :verified,
      listing_ref: payload.listing_ref,
      bundle_ref: payload.bundle_ref
    })

    projected = NodeAccess.attach_projection(node, %{wallet_address: buyer.wallet_address})

    assert projected.paid_payload.status == "active"
    assert projected.paid_payload.delivery_mode == "server_verified"
    assert projected.paid_payload.payment_rail == "onchain"
    assert projected.paid_payload.verified_purchase_count == 1
    assert projected.paid_payload.viewer_has_verified_purchase

    projected_without_entitlement =
      NodeAccess.attach_projection(node, %{wallet_address: seller.wallet_address})

    assert projected_without_entitlement.paid_payload.verified_purchase_count == 1
    refute projected_without_entitlement.paid_payload.viewer_has_verified_purchase

    assert NodeAccess.seller_summary_for_agent(seller.id) == %{
             verified_purchase_count: 1,
             total_sales_usdc: "25.000000"
           }
  end

  test "fetch_payload_for_agent lets the seller read their own active payload" do
    %{seller: seller, node: node} = paid_payload_fixture!()

    assert {:ok, payload} = NodeAccess.fetch_payload_for_agent(node.id, seller)
    assert payload.node_id == node.id
    assert payload.encrypted_payload_uri == "ipfs://bafy-paid-bundle"
    assert payload.download_url =~ "bafy-paid-bundle"
    assert payload.access_policy == %{"price" => "25.000000"}
  end

  test "fetch_payload_for_agent reports missing and inactive payloads" do
    seller = insert_agent_fixture!("seller")
    root = Nodes.create_seed_root!("Evals", "Evals")

    node_without_payload =
      insert_ready_node!(seller, root, %{
        title: "Missing payload node",
        slug: "missing-payload-node"
      })

    assert {:error, :paid_payload_not_found} =
             NodeAccess.fetch_payload_for_agent(node_without_payload.id, seller)

    %{seller: inactive_seller, node: inactive_node} =
      paid_payload_fixture!(payload_status: :draft)

    assert {:error, :paid_payload_not_active} =
             NodeAccess.fetch_payload_for_agent(inactive_node.id, inactive_seller)
  end

  test "paid payloads require IPFS payload locations and EVM settlement addresses" do
    seller = insert_agent_fixture!("seller")
    root = Nodes.create_seed_root!("Evals", "Evals")

    node =
      insert_ready_node!(seller, root, %{
        title: "Invalid paid payload node",
        slug: "invalid-paid-payload-node"
      })

    assert {:error, changeset} =
             NodeAccess.upsert_paid_payload(node, seller, %{
               "status" => "active",
               "encrypted_payload_uri" => "https://example.invalid/payload",
               "payload_hash" => "payload-hash",
               "chain_id" => 84_532,
               "settlement_contract_address" => "not-an-address",
               "usdc_token_address" => "0x0000000000000000000000000000000000008454",
               "treasury_address" => "0x0000000000000000000000000000000000008455",
               "seller_payout_address" => seller.wallet_address,
               "price_usdc" => "25.000000"
             })

    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    assert %{encrypted_payload_uri: ["must use ipfs://"]} = errors
    assert %{settlement_contract_address: ["must be an EVM address"]} = errors
  end

  defp paid_payload_fixture!(opts \\ []) do
    payload_status = Keyword.get(opts, :payload_status, :active)
    seller = insert_agent_fixture!("seller")
    buyer = insert_agent_fixture!("buyer")
    root = Nodes.create_seed_root!("Evals", "Evals")
    uniq = System.unique_integer([:positive])

    node =
      insert_ready_node!(seller, root, %{
        title: "paid-eval-#{uniq}",
        slug: "paid-eval-#{uniq}"
      })

    {:ok, payload} =
      NodeAccess.upsert_paid_payload(node, seller, %{
        "status" => Atom.to_string(payload_status),
        "encrypted_payload_uri" => "ipfs://bafy-paid-bundle",
        "encrypted_payload_cid" => "bafy-paid-bundle",
        "payload_hash" => "paid-bundle-hash",
        "chain_id" => 84_532,
        "settlement_contract_address" => "0x0000000000000000000000000000000000008453",
        "usdc_token_address" => "0x0000000000000000000000000000000000008454",
        "treasury_address" => "0x0000000000000000000000000000000000008455",
        "seller_payout_address" => seller.wallet_address,
        "price_usdc" => "25.000000",
        "encryption_meta" => %{"cipher" => "xchacha20poly1305"},
        "access_policy" => %{"price" => "25.000000"}
      })

    %{seller: seller, buyer: buyer, node: node, payload: payload}
  end

  defp insert_agent_fixture!(label_prefix) do
    token = System.unique_integer([:positive])
    suffix = Integer.to_string(token)

    Repo.insert!(%AgentIdentity{
      chain_id: 84_532,
      registry_address: "0x0000000000000000000000000000000000000001",
      token_id: D.new(token),
      wallet_address: random_eth_address(),
      label: "#{label_prefix}-#{suffix}",
      status: "active"
    })
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end

  defp insert_ready_node!(agent, parent, attrs) do
    uniq = System.unique_integer([:positive])
    parent_path = if is_binary(parent.path), do: parent.path, else: "n#{parent.id}"

    Repo.insert!(%Node{
      path: "#{parent_path}.n#{uniq}",
      depth: (parent.depth || 0) + 1,
      seed: parent.seed,
      kind: Map.get(attrs, :kind, :eval),
      title: Map.fetch!(attrs, :title),
      slug: Map.get(attrs, :slug),
      summary: Map.get(attrs, :summary, "Paid access test node"),
      status: :anchored,
      publish_idempotency_key: "node-access-test-#{uniq}",
      notebook_source: "# notebook",
      parent_id: parent.id,
      creator_agent_id: agent.id,
      activity_score: D.new("10")
    })
  end
end
