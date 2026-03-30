defmodule TechTree.NodeAccess.VerificationTest do
  use ExUnit.Case, async: true

  alias Decimal, as: D
  alias TechTree.NodeAccess.NodePaidPayload
  alias TechTree.NodeAccess.Verification

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
end
