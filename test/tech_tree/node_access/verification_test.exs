defmodule TechTree.NodeAccess.VerificationTest do
  use ExUnit.Case, async: false

  alias Decimal, as: D
  alias TechTree.NodeAccess.NodePaidPayload
  alias TechTree.NodeAccess.Payloads
  alias TechTree.NodeAccess.Verification

  @purchase_settled_event_topic0 "0x55b709eb67e99747eb5949bc3721704e5db6bbc87add708787955b5741bd95fa"
  @rpc_url "http://paid-payload-rpc.test"
  @tx_hash "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @settlement_contract "0x0000000000000000000000000000000000008453"
  @seller_wallet "0x0000000000000000000000000000000000001001"
  @buyer_wallet "0x0000000000000000000000000000000000002002"

  setup do
    original_autoskill = Application.get_env(:tech_tree, :autoskill, [])

    on_exit(fn ->
      Application.put_env(:tech_tree, :autoskill, original_autoskill)
    end)

    :ok
  end

  test "decode_purchase_event parses listing, buyer, seller, and bundle values" do
    assert {:ok, event} =
             Verification.decode_purchase_event(%{
               "topics" => [
                 "0xignored",
                 "0x" <> String.duplicate("a", 64),
                 "0x" <> String.duplicate("0", 24) <> String.duplicate("b", 40),
                 "0x" <> String.duplicate("0", 24) <> String.duplicate("c", 40)
               ],
               "data" =>
                 "0x" <>
                   String.duplicate("d", 64) <>
                   String.pad_leading(Integer.to_string(25_000_000, 16), 64, "0") <>
                   String.pad_leading(Integer.to_string(250_000, 16), 64, "0") <>
                   String.pad_leading(Integer.to_string(24_750_000, 16), 64, "0")
             })

    assert event.listing_ref == "0x" <> String.duplicate("a", 64)
    assert event.bundle_ref == "0x" <> String.duplicate("d", 64)
    assert event.buyer_wallet == "0x" <> String.duplicate("b", 40)
    assert event.seller_wallet == "0x" <> String.duplicate("c", 40)
    assert event.amount_raw == 25_000_000
  end

  test "verify_event rejects a mismatched payout wallet with a stable reason" do
    payload = %NodePaidPayload{
      listing_ref: "0x" <> String.duplicate("a", 64),
      bundle_ref: "0x" <> String.duplicate("d", 64),
      seller_payout_address: "0x" <> String.duplicate("c", 40),
      price_usdc: D.new("25.000000")
    }

    event = %{
      listing_ref: payload.listing_ref,
      bundle_ref: payload.bundle_ref,
      buyer_wallet: "0x" <> String.duplicate("b", 40),
      seller_wallet: "0x" <> String.duplicate("e", 40),
      amount_raw: 25_000_000
    }

    assert {:error, :purchase_seller_mismatch} =
             Verification.verify_event(event, payload, "0x" <> String.duplicate("b", 40))
  end

  test "verify_settlement_tx rejects paid payload purchase receipts from the wrong chain" do
    payload = paid_payload()
    install_rpc!(chain_id: 8_453, receipt: purchase_receipt(payload, @buyer_wallet))

    assert {:error, :purchase_chain_mismatch} =
             Verification.verify_settlement_tx(payload, @tx_hash, @buyer_wallet)
  end

  test "verify_settlement_tx rejects failed paid payload purchase receipts" do
    payload = paid_payload()

    receipt =
      payload
      |> purchase_receipt(@buyer_wallet)
      |> Map.put("status", "0x0")

    install_rpc!(chain_id: payload.chain_id, receipt: receipt)

    assert {:error, :purchase_tx_failed} =
             Verification.verify_settlement_tx(payload, @tx_hash, @buyer_wallet)
  end

  test "verify_settlement_tx rejects malformed paid payload purchase events" do
    payload = paid_payload()
    receipt = purchase_receipt(payload, @buyer_wallet, data: "0x1234")

    install_rpc!(chain_id: payload.chain_id, receipt: receipt)

    assert {:error, :purchase_event_invalid} =
             Verification.verify_settlement_tx(payload, @tx_hash, @buyer_wallet)
  end

  test "verify_settlement_tx rejects paid payload purchase events with the wrong amount" do
    payload = paid_payload()

    receipt =
      purchase_receipt(payload, @buyer_wallet,
        amount: Payloads.decimal_to_micro_units(payload.price_usdc) + 1
      )

    install_rpc!(chain_id: payload.chain_id, receipt: receipt)

    assert {:error, :purchase_amount_mismatch} =
             Verification.verify_settlement_tx(payload, @tx_hash, @buyer_wallet)
  end

  test "verify_settlement_tx rejects paid payload purchase events for a different buyer" do
    payload = paid_payload()
    other_buyer = "0x0000000000000000000000000000000000003003"
    install_rpc!(chain_id: payload.chain_id, receipt: purchase_receipt(payload, other_buyer))

    assert {:error, :purchase_buyer_mismatch} =
             Verification.verify_settlement_tx(payload, @tx_hash, @buyer_wallet)
  end

  defp install_rpc!(opts) do
    chain_id = Keyword.fetch!(opts, :chain_id)
    receipt = Keyword.fetch!(opts, :receipt)

    Application.put_env(:tech_tree, :autoskill,
      chains: %{84_532 => %{rpc_url: @rpc_url}},
      rpc_client: fn
        @rpc_url, %{"method" => "eth_chainId"} ->
          {:ok, %{"result" => "0x" <> Integer.to_string(chain_id, 16)}}

        @rpc_url, %{"method" => "eth_getTransactionReceipt", "params" => [@tx_hash]} ->
          {:ok, %{"result" => receipt}}
      end
    )
  end

  defp paid_payload do
    %NodePaidPayload{
      chain_id: 84_532,
      settlement_contract_address: @settlement_contract,
      seller_payout_address: @seller_wallet,
      price_usdc: D.new("25.000000"),
      listing_ref: "0x" <> String.duplicate("1", 64),
      bundle_ref: "0x" <> String.duplicate("2", 64)
    }
  end

  defp purchase_receipt(payload, buyer_wallet, opts \\ []) do
    amount = Keyword.get(opts, :amount, Payloads.decimal_to_micro_units(payload.price_usdc))
    data = Keyword.get(opts, :data, purchase_data(payload.bundle_ref, amount))

    %{
      "status" => "0x1",
      "logs" => [
        %{
          "address" => payload.settlement_contract_address,
          "topics" => [
            @purchase_settled_event_topic0,
            payload.listing_ref,
            address_topic(buyer_wallet),
            address_topic(payload.seller_payout_address)
          ],
          "data" => data
        }
      ]
    }
  end

  defp purchase_data(bundle_ref, amount) do
    "0x" <>
      String.trim_leading(bundle_ref, "0x") <>
      uint256_word(amount) <>
      uint256_word(1_000_000) <>
      uint256_word(amount - 1_000_000)
  end

  defp address_topic("0x" <> address), do: "0x" <> String.duplicate("0", 24) <> address

  defp uint256_word(value) do
    value
    |> Integer.to_string(16)
    |> String.pad_leading(64, "0")
  end
end
