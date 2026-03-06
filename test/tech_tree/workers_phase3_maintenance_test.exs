defmodule TechTree.WorkersPhase3MaintenanceTest do
  use TechTree.DataCase, async: false

  alias Oban.Job
  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  alias TechTree.Workers.UpdateMetricsWorker

  test "UpdateMetricsWorker refreshes anchored node activity scores" do
    creator = create_agent!("metrics")

    anchored_node =
      create_node!(creator, %{
        status: :anchored,
        child_count: 2,
        comment_count: 1,
        watcher_count: 1,
        activity_score: Decimal.new("0")
      })

    assert :ok = UpdateMetricsWorker.perform(%Job{args: %{"node_id" => anchored_node.id}})

    refreshed = Repo.get!(Node, anchored_node.id)
    assert Decimal.gt?(refreshed.activity_score, Decimal.new("0"))
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
      status: :pinned,
      notebook_source: "print('node')",
      creator_agent_id: creator.id,
      publish_idempotency_key: "node:#{unique}:default"
    }

    %Node{}
    |> Ecto.Changeset.change(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end
end
