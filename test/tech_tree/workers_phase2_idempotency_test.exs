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
    UpdateMetricsWorker
  }

  test "AnchorNodeWorker is idempotent and tracks a single submitted publish attempt" do
    creator = create_agent!("anchor")

    node =
      create_node!(creator, %{
        status: :pinned,
        manifest_uri: "ipfs://manifest-anchor",
        manifest_hash: "deadbeefanchor",
        tx_hash: "0x" <> String.duplicate("a", 64),
        publish_idempotency_key: "node:#{System.unique_integer([:positive])}:deadbeefanchor"
      })

    args = %{
      "node_id" => node.id,
      "idempotency_key" => node.publish_idempotency_key
    }

    assert :ok = AnchorNodeWorker.perform(%Job{args: args})
    assert :ok = AnchorNodeWorker.perform(%Job{args: args})

    assert count_jobs(AwaitNodeReceiptWorker, node.id) == 1

    attempt = fetch_publish_attempt!(node.publish_idempotency_key)
    assert attempt["tx_hash"] == node.tx_hash
    assert attempt["attempt_count"] == 1
    assert attempt["status"] == "awaiting_receipt"
  end

  test "AwaitNodeReceiptWorker is idempotent after node becomes anchored" do
    creator = create_agent!("await")

    node =
      create_node!(creator, %{
        status: :pinned,
        manifest_cid: "bafy-manifest-await",
        manifest_uri: "ipfs://manifest-await",
        manifest_hash: "deadbeefawait",
        notebook_cid: "bafy-notebook-await",
        tx_hash: "0x" <> String.duplicate("b", 64),
        publish_idempotency_key: "node:#{System.unique_integer([:positive])}:deadbeefawait"
      })

    _ =
      Repo.insert_all("node_publish_attempts", [
        %{
          node_id: node.id,
          idempotency_key: node.publish_idempotency_key,
          manifest_uri: node.manifest_uri,
          manifest_hash: node.manifest_hash,
          tx_hash: node.tx_hash,
          status: "awaiting_receipt",
          attempt_count: 1,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }
      ])

    args = %{
      "node_id" => node.id,
      "tx_hash" => node.tx_hash,
      "idempotency_key" => node.publish_idempotency_key
    }

    assert :ok = AwaitNodeReceiptWorker.perform(%Job{args: args})
    assert :ok = AwaitNodeReceiptWorker.perform(%Job{args: args})

    anchored_node = Repo.get!(Node, node.id)
    assert anchored_node.status == :anchored
    assert count_receipts(node.id) == 1

    assert count_jobs(IndexNodeWorker, node.id) == 1
    assert count_jobs(UpdateMetricsWorker, node.id) == 1
    assert count_jobs(BroadcastNodeReadyWorker, node.id) == 1
    assert count_jobs(FanoutWatcherNotificationsWorker, node.id) == 1

    attempt = fetch_publish_attempt!(node.publish_idempotency_key)
    assert attempt["status"] == "anchored"
    assert attempt["tx_hash"] == node.tx_hash
  end

  defp create_agent!(label_prefix) do
    unique = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => "84532",
      "registry_address" => random_eth_address(),
      "token_id" => Integer.to_string(unique),
      "wallet_address" => random_eth_address(),
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
      status: :pinned,
      notebook_source: "print('node')",
      creator_agent_id: creator.id,
      publish_idempotency_key: "node:#{unique}:default"
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

  defp fetch_publish_attempt!(idempotency_key) do
    from(p in "node_publish_attempts",
      where: p.idempotency_key == ^idempotency_key,
      select: %{
        "tx_hash" => p.tx_hash,
        "attempt_count" => p.attempt_count,
        "status" => p.status
      }
    )
    |> Repo.one!()
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end
end
