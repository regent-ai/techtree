defmodule TechTree.Nodes.Publishing.Transitions do
  @moduledoc false

  alias TechTree.Nodes.Node

  def anchored_decision(%Node{status: :anchored, tx_hash: existing_tx_hash}, tx_hash) do
    if existing_tx_hash == tx_hash do
      {:already_transitioned, :matching_tx_hash}
    else
      {:error, :mismatched_tx_hash}
    end
  end

  def anchored_decision(%Node{status: :pinned, tx_hash: existing_tx_hash}, tx_hash) do
    if is_binary(existing_tx_hash) and byte_size(existing_tx_hash) > 0 and
         existing_tx_hash != tx_hash do
      {:error, :mismatched_pending_tx_hash}
    else
      {:transition, :receipt_recorded}
    end
  end

  def anchored_decision(%Node{status: status}, _tx_hash), do: {:invalid_status, status}

  def failed_anchor_decision(%Node{status: :failed_anchor}),
    do: {:already_transitioned, :already_failed_anchor}

  def failed_anchor_decision(%Node{status: :pinned}), do: {:transition, :anchor_attempt_exhausted}

  def failed_anchor_decision(%Node{status: :anchored}),
    do: {:already_transitioned, :already_anchored}

  def failed_anchor_decision(%Node{status: status}), do: {:invalid_status, status}
end
