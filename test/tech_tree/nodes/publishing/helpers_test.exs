defmodule TechTree.Nodes.Publishing.HelpersTest do
  use ExUnit.Case, async: true

  alias TechTree.Nodes.Node
  alias TechTree.Nodes.Publishing.{Attrs, PublishAttempts, Transitions}

  test "normalize_create_attrs keeps ids, paid payload maps, and idempotency keys consistent" do
    assert %{
             "parent_id" => 42,
             "paid_payload" => %{"status" => "draft"},
             "publish_idempotency_key" => "request-42"
           } =
             Attrs.normalize_create_attrs(%{
               parent_id: "42",
               paid_payload: %{status: "draft"},
               idempotency_key: " request-42 "
             })
  end

  test "anchored_decision rejects mismatched pending transactions before state changes" do
    node = %Node{status: :pinned, tx_hash: "0x" <> String.duplicate("a", 64)}

    assert {:error, :mismatched_pending_tx_hash} =
             Transitions.anchored_decision(node, "0x" <> String.duplicate("b", 64))
  end

  test "publish attempt update fields increment retry count only for retry states" do
    {set_fields, inc_fields} =
      PublishAttempts.normalize_publish_attempt_update_fields(
        %{status: "failed_anchor", tx_hash: "0xabc"},
        "failed_anchor"
      )

    assert Keyword.get(inc_fields, :attempt_count) == 1
    assert Keyword.get(set_fields, :status) == "failed_anchor"
    assert Keyword.has_key?(set_fields, :last_error)
  end
end
