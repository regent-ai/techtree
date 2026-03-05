defmodule TechTree.WorkersPhase3MaintenanceTest do
  use TechTree.DataCase, async: false

  alias Oban.Job
  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  alias TechTree.Workers.{
    AnchorNodeWorker,
    AwaitNodeReceiptWorker,
    PackageAndPinNodeWorker,
    ReconcileBaseNodesWorker,
    UpdateMetricsWorker,
    VerifyPinnedArtifactsWorker
  }

  test "ReconcileBaseNodesWorker idempotently enqueues await jobs for pending chain receipts" do
    creator = create_agent!("reconcile")

    node =
      create_node!(creator, %{
        status: :pending_chain,
        manifest_cid: "manifest-reconcile",
        manifest_uri: "ipfs://manifest-reconcile",
        manifest_hash: "hash-reconcile",
        notebook_cid: "notebook-reconcile",
        tx_hash: "0xreconciletx"
      })

    assert :ok = ReconcileBaseNodesWorker.perform(%Job{args: %{}})
    assert :ok = ReconcileBaseNodesWorker.perform(%Job{args: %{}})

    assert count_jobs(AwaitNodeReceiptWorker, node.id) == 1
  end

  test "VerifyPinnedArtifactsWorker repairs invalid artifacts and anchors valid pending chain nodes" do
    creator = create_agent!("verify")

    valid_node =
      create_node!(creator, %{
        status: :pending_chain,
        manifest_cid: "manifest-verify",
        manifest_uri: "ipfs://manifest-verify",
        manifest_hash: "hash-verify",
        notebook_cid: "notebook-verify",
        tx_hash: nil
      })

    invalid_node =
      create_node!(creator, %{
        status: :pending_chain,
        manifest_cid: "manifest-invalid",
        manifest_uri: nil,
        manifest_hash: nil,
        notebook_cid: nil,
        tx_hash: nil
      })

    assert :ok = VerifyPinnedArtifactsWorker.perform(%Job{args: %{}})
    assert :ok = VerifyPinnedArtifactsWorker.perform(%Job{args: %{}})

    assert count_jobs(AnchorNodeWorker, valid_node.id) == 1
    assert count_jobs(PackageAndPinNodeWorker, invalid_node.id) == 1
  end

  test "UpdateMetricsWorker updates ready nodes and skips non-ready nodes safely" do
    creator = create_agent!("metrics")

    ready_node =
      create_node!(creator, %{
        status: :ready,
        child_count: 2,
        comment_count: 1,
        watcher_count: 1,
        activity_score: Decimal.new("0")
      })

    pending_node =
      create_node!(creator, %{
        status: :pending_ipfs,
        child_count: 5,
        comment_count: 5,
        watcher_count: 5,
        activity_score: Decimal.new("7")
      })

    assert :ok = UpdateMetricsWorker.perform(%Job{args: %{"node_id" => ready_node.id}})
    assert :ok = UpdateMetricsWorker.perform(%Job{args: %{"node_id" => pending_node.id}})

    refreshed_ready_node = Repo.get!(Node, ready_node.id)
    refreshed_pending_node = Repo.get!(Node, pending_node.id)

    assert Decimal.gt?(refreshed_ready_node.activity_score, Decimal.new("0"))
    assert Decimal.equal?(refreshed_pending_node.activity_score, Decimal.new("7"))
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
      title: "phase3-node-#{unique}",
      status: :pending_chain,
      notebook_source: "print('node')",
      creator_agent_id: creator.id
    }

    %Node{}
    |> Ecto.Changeset.change(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end

  defp count_jobs(worker_module, node_id) do
    worker_name = worker_module |> Module.split() |> Enum.join(".")

    Job
    |> where([j], j.worker == ^worker_name)
    |> where([j], fragment("? ->> 'node_id' = ?", j.args, ^to_string(node_id)))
    |> Repo.aggregate(:count, :id)
  end
end
