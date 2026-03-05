defmodule TechTree.NodesTransitionTest do
  use TechTree.DataCase, async: false

  @transition_event [:tech_tree, :nodes, :transition]

  alias TechTree.Agents
  alias TechTree.Nodes
  alias TechTree.Nodes.{Node, NodeChainReceipt}
  alias TechTree.Repo

  describe "mark_node_pending_chain!/2" do
    test "returns already_transitioned for ready nodes" do
      creator = create_agent!("pending-ready")

      node =
        create_node!(creator, %{
          status: :ready,
          manifest_uri: "ipfs://existing-ready",
          manifest_hash: "existing-ready-hash"
        })

      result =
        Nodes.mark_node_pending_chain!(node.id, %{
          manifest_cid: "bafy-new",
          manifest_uri: "ipfs://new",
          manifest_hash: "new-hash",
          notebook_cid: "bafy-notebook-new"
        })

      assert result == :already_transitioned
      assert Repo.get!(Node, node.id).status == :ready
    end

    test "returns already_transitioned for identical pending_chain payloads" do
      creator = create_agent!("pending-same")

      node =
        create_node!(creator, %{
          status: :pending_chain,
          manifest_cid: "bafy-same-manifest",
          manifest_uri: "ipfs://same-manifest",
          manifest_hash: "same-manifest-hash",
          notebook_cid: "bafy-same-notebook"
        })

      result =
        Nodes.mark_node_pending_chain!(node.id, %{
          manifest_cid: node.manifest_cid,
          manifest_uri: node.manifest_uri,
          manifest_hash: node.manifest_hash,
          notebook_cid: node.notebook_cid
        })

      assert result == :already_transitioned
    end

    test "transitions pending_ipfs nodes to pending_chain with materialized payload" do
      creator = create_agent!("pending-ipfs")
      node = create_node!(creator, %{status: :pending_ipfs})

      result =
        Nodes.mark_node_pending_chain!(node.id, %{
          manifest_cid: "bafy-materialized",
          manifest_uri: "ipfs://materialized",
          manifest_hash: "materialized-hash",
          notebook_cid: "bafy-notebook-materialized"
        })

      transitioned = Repo.get!(Node, node.id)

      assert result == :transitioned
      assert transitioned.status == :pending_chain
      assert transitioned.manifest_uri == "ipfs://materialized"
      assert transitioned.manifest_hash == "materialized-hash"
      assert transitioned.manifest_cid == "bafy-materialized"
      assert transitioned.notebook_cid == "bafy-notebook-materialized"
    end

    test "rejects pending_chain payload mutation once tx hash is assigned" do
      creator = create_agent!("pending-immutable")

      node =
        create_node!(creator, %{
          status: :pending_chain,
          manifest_cid: "bafy-immutable",
          manifest_uri: "ipfs://immutable",
          manifest_hash: "immutable-hash",
          notebook_cid: "bafy-immutable-notebook",
          tx_hash: "0ximmutabletx"
        })

      assert_raise ArgumentError, ~r/after tx hash assignment/, fn ->
        Nodes.mark_node_pending_chain!(node.id, %{
          manifest_cid: "bafy-new",
          manifest_uri: "ipfs://new",
          manifest_hash: "new-hash",
          notebook_cid: "bafy-new-notebook"
        })
      end

      persisted = Repo.get!(Node, node.id)
      assert persisted.manifest_uri == node.manifest_uri
      assert persisted.manifest_hash == node.manifest_hash
      assert persisted.status == :pending_chain
    end

    test "emits transition telemetry at boundary" do
      creator = create_agent!("pending-telemetry")
      node = create_node!(creator, %{status: :pending_ipfs})

      handler_id = "nodes-transition-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler_id,
          @transition_event,
          fn event, measurements, metadata, pid ->
            send(pid, {:transition_telemetry, event, measurements, metadata})
          end,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :transitioned =
               Nodes.mark_node_pending_chain!(node.id, %{
                 manifest_cid: "bafy-telemetry",
                 manifest_uri: "ipfs://telemetry",
                 manifest_hash: "telemetry-hash",
                 notebook_cid: "bafy-telemetry-notebook"
               })

      assert_receive {:transition_telemetry, @transition_event, %{count: 1}, metadata}
      assert metadata.node_id == node.id
      assert metadata.from_status == "pending_ipfs"
      assert metadata.to_status == "pending_chain"
      assert metadata.outcome == "transitioned"
    end
  end

  describe "mark_node_ready!/2" do
    test "transitions pending_chain node and remains idempotent for same tx_hash" do
      creator = create_agent!("ready-idempotent")

      node =
        create_node!(creator, %{
          status: :pending_chain,
          manifest_cid: "bafy-ready-manifest",
          manifest_uri: "ipfs://ready-manifest",
          manifest_hash: "ready-manifest-hash",
          notebook_cid: "bafy-ready-notebook",
          tx_hash: "0xreadytx"
        })

      attrs = %{
        tx_hash: "0xreadytx",
        chain_id: 8453,
        contract_address: "0xreadycontract",
        block_number: 123,
        log_index: 0
      }

      assert Nodes.mark_node_ready!(node.id, attrs) == :transitioned
      assert Nodes.mark_node_ready!(node.id, attrs) == :already_transitioned

      ready_node = Repo.get!(Node, node.id)

      assert ready_node.status == :ready
      assert count_receipts(node.id) == 1
    end

    test "raises for pending_chain node when tx_hash mismatches existing pending tx_hash" do
      creator = create_agent!("ready-mismatch")

      node =
        create_node!(creator, %{
          status: :pending_chain,
          manifest_cid: "bafy-mismatch-manifest",
          manifest_uri: "ipfs://mismatch-manifest",
          manifest_hash: "mismatch-manifest-hash",
          notebook_cid: "bafy-mismatch-notebook",
          tx_hash: "0xexpectedtx"
        })

      assert_raise ArgumentError, ~r/mismatched pending tx hash/, fn ->
        Nodes.mark_node_ready!(node.id, %{
          tx_hash: "0xother",
          chain_id: 8453,
          contract_address: "0xmismatchcontract",
          block_number: 777
        })
      end
    end

    test "rolls back status when receipt insert fails after ready update" do
      creator = create_agent!("ready-rollback")

      node =
        create_node!(creator, %{
          status: :pending_chain,
          manifest_cid: "bafy-rollback",
          manifest_uri: "ipfs://rollback",
          manifest_hash: "rollback-hash",
          notebook_cid: "bafy-rollback-notebook",
          tx_hash: "0xrollbacktx"
        })

      assert_raise Ecto.InvalidChangesetError, fn ->
        Nodes.mark_node_ready!(node.id, %{
          tx_hash: "0xrollbacktx",
          chain_id: 8453,
          contract_address: "0xrollbackcontract"
        })
      end

      persisted = Repo.get!(Node, node.id)
      assert persisted.status == :pending_chain
      assert count_receipts(node.id) == 0
    end

    test "raises when ready receipt payload conflicts with existing receipt" do
      creator = create_agent!("ready-receipt-mismatch")

      node =
        create_node!(creator, %{
          status: :pending_chain,
          manifest_cid: "bafy-receipt",
          manifest_uri: "ipfs://receipt",
          manifest_hash: "receipt-hash",
          notebook_cid: "bafy-receipt-notebook",
          tx_hash: "0xreceipttx"
        })

      attrs = %{
        tx_hash: "0xreceipttx",
        chain_id: 8453,
        contract_address: "0xreceiptcontract",
        block_number: 555,
        log_index: 7
      }

      assert :transitioned = Nodes.mark_node_ready!(node.id, attrs)

      assert_raise ArgumentError, ~r/node chain receipt mismatch/, fn ->
        Nodes.mark_node_ready!(node.id, Map.put(attrs, :block_number, 556))
      end
    end
  end

  defp create_agent!(label_prefix) do
    unique = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => "8453",
      "registry_address" => "0x#{label_prefix}registry#{unique}",
      "token_id" => Integer.to_string(unique),
      "wallet_address" => "0x#{label_prefix}wallet#{unique}",
      "label" => "#{label_prefix}-#{unique}"
    })
  end

  defp create_node!(creator, attrs) do
    unique = System.unique_integer([:positive])

    base_attrs = %{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "transition-node-#{unique}",
      status: :pending_chain,
      notebook_source: "print('transition')",
      creator_agent_id: creator.id
    }

    %Node{}
    |> Ecto.Changeset.change(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end

  defp count_receipts(node_id) do
    NodeChainReceipt
    |> where([receipt], receipt.node_id == ^node_id)
    |> Repo.aggregate(:count, :id)
  end
end
