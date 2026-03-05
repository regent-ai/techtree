defmodule TechTree.WorkersPhase2IdempotencyTest do
  use TechTree.DataCase, async: false

  alias Oban.Job
  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Nodes.NodeChainReceipt
  alias TechTree.Repo

  alias TechTree.Workers.{
    AnchorNodeWorker,
    AwaitNodeReceiptWorker,
    BroadcastNodeReadyWorker,
    FanoutWatcherNotificationsWorker,
    IndexNodeWorker,
    PackageAndPinNodeWorker,
    UpdateMetricsWorker
  }

  test "PackageAndPinNodeWorker is idempotent when node already has manifest payload" do
    creator = create_agent!("package-pin")

    node =
      create_node!(creator, %{
        status: :pending_chain,
        manifest_cid: "bafy-manifest-package-pin",
        manifest_uri: "ipfs://manifest-package-pin",
        manifest_hash: "deadbeefpackagepin",
        notebook_cid: "bafy-notebook-package-pin"
      })

    assert :ok = PackageAndPinNodeWorker.perform(%Job{args: %{"node_id" => node.id}})
    assert :ok = PackageAndPinNodeWorker.perform(%Job{args: %{"node_id" => node.id}})

    assert count_jobs(AnchorNodeWorker, node.id) == 1
  end

  test "AnchorNodeWorker is idempotent when tx_hash is already assigned" do
    creator = create_agent!("anchor")

    node =
      create_node!(creator, %{
        status: :pending_chain,
        manifest_uri: "ipfs://manifest-anchor",
        manifest_hash: "deadbeefanchor",
        tx_hash: "0x" <> String.duplicate("a", 64)
      })

    args = %{
      "node_id" => node.id,
      "manifest_uri" => node.manifest_uri,
      "manifest_hash" => node.manifest_hash
    }

    assert :ok = AnchorNodeWorker.perform(%Job{args: args})
    assert :ok = AnchorNodeWorker.perform(%Job{args: args})

    assert count_jobs(AwaitNodeReceiptWorker, node.id) == 1
  end

  test "AwaitNodeReceiptWorker is idempotent after node becomes ready" do
    creator = create_agent!("await")

    node =
      create_node!(creator, %{
        status: :pending_chain,
        manifest_cid: "bafy-manifest-await",
        manifest_uri: "ipfs://manifest-await",
        manifest_hash: "deadbeefawait",
        notebook_cid: "bafy-notebook-await",
        tx_hash: "0x" <> String.duplicate("b", 64)
      })

    args = %{
      "node_id" => node.id,
      "tx_hash" => node.tx_hash,
      "manifest_uri" => node.manifest_uri,
      "manifest_hash" => node.manifest_hash
    }

    assert :ok = AwaitNodeReceiptWorker.perform(%Job{args: args})
    assert :ok = AwaitNodeReceiptWorker.perform(%Job{args: args})

    ready_node = Repo.get!(Node, node.id)
    assert ready_node.status == :ready
    assert count_receipts(node.id) == 1

    assert count_jobs(IndexNodeWorker, node.id) == 1
    assert count_jobs(UpdateMetricsWorker, node.id) == 1
    assert count_jobs(BroadcastNodeReadyWorker, node.id) == 1
    assert count_jobs(FanoutWatcherNotificationsWorker, node.id) == 1
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
      title: "worker-node-#{unique}",
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

  defp count_receipts(node_id) do
    NodeChainReceipt
    |> where([receipt], receipt.node_id == ^node_id)
    |> Repo.aggregate(:count, :id)
  end
end
