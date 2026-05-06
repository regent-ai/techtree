defmodule TechTreeWeb.AgentNodeAccessControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import TechTree.PhaseDApiSupport

  alias Decimal, as: D
  alias TechTree.Agents
  alias TechTree.Autoskill.NodeBundle
  alias TechTree.NodeAccess
  alias TechTree.NodeAccess.NodePaidPayload
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  @purchase_settled_topic0 "0x55b709eb67e99747eb5949bc3721704e5db6bbc87add708787955b5741bd95fa"
  @price_usdc "25.000000"
  @price_micro_units 25_000_000
  @treasury_micro_units 250_000
  @seller_micro_units 24_750_000

  setup do
    previous = Application.get_env(:tech_tree, :autoskill)

    on_exit(fn ->
      if previous do
        Application.put_env(:tech_tree, :autoskill, previous)
      else
        Application.delete_env(:tech_tree, :autoskill)
      end
    end)

    :ok
  end

  test "verified purchase unlocks node payloads and gated autoskill bundles", %{conn: conn} do
    %{seller: seller, buyer: buyer, node: node, payload: payload, payee_wallet: payee_wallet} =
      paid_eval_fixture!()

    configure_autoskill_rpc!(payload, buyer.wallet_address, payee_wallet)

    buyer_conn =
      conn
      |> with_siwa_headers(
        wallet: buyer.wallet_address,
        chain_id: Integer.to_string(buyer.chain_id),
        registry_address: buyer.registry_address,
        token_id: Decimal.to_string(buyer.token_id)
      )

    assert %{"error" => %{"code" => "autoskill_payment_required"}} =
             conn
             |> put_req_header("accept", "application/json")
             |> get("/v1/autoskill/versions/#{node.id}/bundle")
             |> json_response(402)

    assert %{
             "data" => %{
               "node_id" => node_id,
               "tx_hash" => _tx_hash,
               "chain_id" => 8_453,
               "amount_usdc" => @price_usdc,
               "listing_ref" => listing_ref,
               "bundle_ref" => bundle_ref
             }
           } =
             buyer_conn
             |> post("/v1/agent/tree/nodes/#{node.id}/purchases", %{"tx_hash" => tx_hash()})
             |> json_response(201)

    assert node_id == node.id
    assert listing_ref == payload.listing_ref
    assert bundle_ref == payload.bundle_ref
    assert payload.seller_payout_address == payee_wallet
    refute payload.seller_payout_address == seller.wallet_address

    assert %{
             "data" => %{
               "node_id" => ^node_id,
               "encrypted_payload_uri" => "ipfs://bafy-paid-bundle",
               "download_url" => download_url
             }
           } =
             buyer_conn
             |> get("/v1/agent/tree/nodes/#{node.id}/payload")
             |> json_response(200)

    assert String.contains?(download_url, "bafy-paid-bundle")

    assert %{
             "data" => %{
               "node_id" => ^node_id,
               "bundle_uri" => "ipfs://bafy-paid-bundle",
               "download_url" => bundle_download_url
             }
           } =
             buyer_conn
             |> get("/v1/agent/autoskill/versions/#{node.id}/bundle")
             |> json_response(200)

    assert String.contains?(bundle_download_url, "bafy-paid-bundle")

    assert %{
             "data" => %{
               "id" => ^node_id,
               "paid_payload" => %{
                 "verified_purchase_count" => 1,
                 "viewer_has_verified_purchase" => true
               }
             }
           } =
             buyer_conn
             |> get("/v1/agent/tree/nodes/#{node.id}")
             |> json_response(200)

    assert NodeAccess.seller_summary_for_wallet(seller.wallet_address) == %{
             verified_purchase_count: 1,
             total_sales_usdc: @price_usdc
           }

    assert %{"error" => %{"code" => "duplicate_purchase_tx"}} =
             buyer_conn
             |> post("/v1/agent/tree/nodes/#{node.id}/purchases", %{"tx_hash" => tx_hash()})
             |> json_response(422)

    assert %{"error" => %{"code" => "autoskill_payment_required"}} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/autoskill/versions/#{node.id}/bundle")
             |> json_response(402)
  end

  test "purchase verification rejects mismatched settlement proofs", %{conn: conn} do
    %{seller: seller, buyer: buyer, node: node, payload: payload} = paid_eval_fixture!()

    configure_autoskill_rpc!(payload, buyer.wallet_address, random_eth_address())

    buyer_conn =
      conn
      |> with_siwa_headers(
        wallet: buyer.wallet_address,
        chain_id: Integer.to_string(buyer.chain_id),
        registry_address: buyer.registry_address,
        token_id: Decimal.to_string(buyer.token_id)
      )

    assert %{"error" => %{"code" => "purchase_verification_failed", "message" => message}} =
             buyer_conn
             |> post("/v1/agent/tree/nodes/#{node.id}/purchases", %{"tx_hash" => tx_hash()})
             |> json_response(422)

    assert message == "We could not verify that purchase. Check the transaction and try again."
    refute message =~ "purchase_"

    assert NodeAccess.seller_summary_for_wallet(seller.wallet_address) == %{
             verified_purchase_count: 0,
             total_sales_usdc: "0"
           }

    assert %{"error" => %{"code" => "paid_payload_payment_required"}} =
             buyer_conn
             |> get("/v1/agent/tree/nodes/#{node.id}/payload")
             |> json_response(402)
  end

  test "seller can fetch their own active payload without a purchase", %{conn: conn} do
    %{seller: seller, node: node} = paid_eval_fixture!()

    seller_conn =
      conn
      |> with_siwa_headers(
        wallet: seller.wallet_address,
        chain_id: Integer.to_string(seller.chain_id),
        registry_address: seller.registry_address,
        token_id: Decimal.to_string(seller.token_id)
      )

    assert %{
             "data" => %{
               "node_id" => node_id,
               "encrypted_payload_uri" => "ipfs://bafy-paid-bundle",
               "download_url" => download_url
             }
           } =
             seller_conn
             |> get("/v1/agent/tree/nodes/#{node.id}/payload")
             |> json_response(200)

    assert node_id == node.id
    assert String.contains?(download_url, "bafy-paid-bundle")
  end

  test "payload endpoint reports malformed ids, missing payloads, and inactive payloads", %{
    conn: conn
  } do
    requester = insert_agent!("requester")
    root = Nodes.create_seed_root!("Evals", "Evals")

    node_without_payload =
      Repo.insert!(%Node{
        path: "n#{root.id}.n#{unique_suffix()}",
        depth: 1,
        seed: "Evals",
        kind: :eval,
        title: "missing-payload-#{unique_suffix()}",
        slug: "missing-payload-#{unique_suffix()}",
        summary: "Node without paid payload",
        status: :anchored,
        publish_idempotency_key: "missing-payload:#{unique_suffix()}",
        notebook_source: "# missing payload",
        parent_id: root.id,
        creator_agent_id: requester.id,
        activity_score: D.new("3")
      })

    %{node: inactive_node} = paid_eval_fixture!(payload_status: "draft")

    requester_conn =
      conn
      |> with_siwa_headers(
        wallet: requester.wallet_address,
        chain_id: Integer.to_string(requester.chain_id),
        registry_address: requester.registry_address,
        token_id: Decimal.to_string(requester.token_id)
      )

    assert %{"error" => %{"code" => "invalid_node_id"}} =
             requester_conn
             |> get("/v1/agent/tree/nodes/not-an-id/payload")
             |> json_response(422)

    assert %{"error" => %{"code" => "paid_payload_not_found"}} =
             requester_conn
             |> get("/v1/agent/tree/nodes/#{node_without_payload.id}/payload")
             |> json_response(404)

    assert %{"error" => %{"code" => "paid_payload_not_active"}} =
             requester_conn
             |> get("/v1/agent/tree/nodes/#{inactive_node.id}/payload")
             |> json_response(422)
  end

  test "purchase endpoint reports inactive payloads", %{conn: conn} do
    %{buyer: buyer, node: node} = paid_eval_fixture!(payload_status: "draft")

    buyer_conn =
      conn
      |> with_siwa_headers(
        wallet: buyer.wallet_address,
        chain_id: Integer.to_string(buyer.chain_id),
        registry_address: buyer.registry_address,
        token_id: Decimal.to_string(buyer.token_id)
      )

    assert %{"error" => %{"code" => "paid_payload_not_active"}} =
             buyer_conn
             |> post("/v1/agent/tree/nodes/#{node.id}/purchases", %{"tx_hash" => tx_hash()})
             |> json_response(422)
  end

  defp paid_eval_fixture!(opts \\ []) do
    seller = insert_agent!("seller")
    buyer = insert_agent!("buyer")
    payee_wallet = random_eth_address()
    root = Nodes.create_seed_root!("Evals", "Evals")
    uniq = System.unique_integer([:positive])
    payload_status = Keyword.get(opts, :payload_status, "active")

    node =
      Repo.insert!(%Node{
        path: "n#{root.id}.n#{uniq}",
        depth: 1,
        seed: "Evals",
        kind: :eval,
        title: "paid-eval-#{uniq}",
        slug: "paid-eval-#{uniq}",
        summary: "Paid eval node",
        status: :anchored,
        publish_idempotency_key: "paid-eval:#{uniq}",
        notebook_source: "# paid eval",
        parent_id: root.id,
        creator_agent_id: seller.id,
        activity_score: D.new("10")
      })

    Repo.insert!(%NodeBundle{
      node_id: node.id,
      bundle_type: :eval,
      access_mode: :gated_paid,
      preview_md: "# Paid benchmark",
      bundle_manifest: %{"metadata" => %{"version" => "0.1.0"}},
      primary_file: "scenario.yaml",
      marimo_entrypoint: "session.marimo.py",
      encrypted_bundle_uri: "ipfs://bafy-paid-bundle",
      encrypted_bundle_cid: "bafy-paid-bundle",
      bundle_hash: "paid-bundle-hash",
      payment_rail: :onchain,
      access_policy: %{"price" => @price_usdc}
    })

    {:ok, payload} =
      NodeAccess.upsert_paid_payload(node, seller, %{
        "status" => payload_status,
        "encrypted_payload_uri" => "ipfs://bafy-paid-bundle",
        "encrypted_payload_cid" => "bafy-paid-bundle",
        "payload_hash" => "paid-bundle-hash",
        "chain_id" => 8_453,
        "settlement_contract_address" => settlement_contract(),
        "usdc_token_address" => usdc_token(),
        "treasury_address" => treasury_address(),
        "seller_payout_address" => payee_wallet,
        "price_usdc" => @price_usdc,
        "encryption_meta" => %{"cipher" => "xchacha20poly1305"}
      })

    %{seller: seller, buyer: buyer, node: node, payload: payload, payee_wallet: payee_wallet}
  end

  defp configure_autoskill_rpc!(%NodePaidPayload{} = payload, buyer_wallet, seller_wallet) do
    Application.put_env(:tech_tree, :autoskill,
      chains: %{
        8_453 => %{
          rpc_url: "http://rpc.test",
          settlement_contract_address: payload.settlement_contract_address,
          usdc_token_address: payload.usdc_token_address,
          treasury_address: payload.treasury_address
        }
      },
      rpc_client: fn _rpc_url, rpc_payload ->
        case rpc_payload["method"] do
          "eth_chainId" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => rpc_payload["id"], "result" => "0x2105"}}

          "eth_getTransactionReceipt" ->
            {:ok,
             %{
               "jsonrpc" => "2.0",
               "id" => rpc_payload["id"],
               "result" => %{
                 "status" => "0x1",
                 "logs" => [
                   %{
                     "address" => payload.settlement_contract_address,
                     "topics" => [
                       @purchase_settled_topic0,
                       payload.listing_ref,
                       encode_topic_address(buyer_wallet),
                       encode_topic_address(seller_wallet)
                     ],
                     "data" =>
                       encode_purchase_data(
                         payload.bundle_ref,
                         @price_micro_units,
                         @treasury_micro_units,
                         @seller_micro_units
                       )
                   }
                 ]
               }
             }}
        end
      end
    )
  end

  defp insert_agent!(label) do
    Agents.upsert_verified_agent!(%{
      "chain_id" => "8453",
      "registry_address" => random_eth_address(),
      "token_id" => Integer.to_string(unique_suffix()),
      "wallet_address" => random_eth_address(),
      "label" => "#{label}-#{unique_suffix()}",
      "status" => "active"
    })
  end

  defp settlement_contract, do: "0x0000000000000000000000000000000000008453"
  defp usdc_token, do: "0x0000000000000000000000000000000000008454"
  defp treasury_address, do: "0x0000000000000000000000000000000000008455"
  defp tx_hash, do: "0x" <> String.duplicate("a", 64)

  defp encode_topic_address("0x" <> address_hex) do
    "0x" <> String.duplicate("0", 24) <> String.downcase(address_hex)
  end

  defp encode_purchase_data(bundle_ref, amount, treasury_amount, seller_amount) do
    "0x" <>
      strip_0x(bundle_ref) <>
      encode_u256(amount) <>
      encode_u256(treasury_amount) <>
      encode_u256(seller_amount)
  end

  defp encode_u256(value) when is_integer(value) and value >= 0 do
    value
    |> Integer.to_string(16)
    |> String.pad_leading(64, "0")
  end

  defp strip_0x("0x" <> value), do: String.downcase(value)
end
