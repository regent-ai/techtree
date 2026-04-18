defmodule TechTree.WorkersPhase3MaintenanceTest do
  use TechTree.DataCase, async: false

  alias Oban.Job
  alias TechTree.Agents
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.RateLimit
  alias TechTree.Repo
  alias TechTree.Workers.IndexCommentWorker
  alias TechTree.Workers.RebuildHotScoresWorker
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

  test "refresh_hot_scores! uses the same canonical formula as UpdateMetricsWorker" do
    creator = create_agent!("metrics-canonical")

    anchored_node =
      create_node!(creator, %{
        status: :anchored,
        child_count: 4,
        comment_count: 2,
        watcher_count: 3,
        activity_score: Decimal.new("0")
      })

    assert :ok = UpdateMetricsWorker.perform(%Job{args: %{"node_id" => anchored_node.id}})
    worker_score = Repo.get!(Node, anchored_node.id).activity_score

    assert :ok =
             anchored_node
             |> Ecto.Changeset.change(activity_score: Decimal.new("0"))
             |> Repo.update()
             |> then(fn {:ok, _node} -> :ok end)

    assert :ok = Nodes.refresh_hot_scores!()
    rebuild_score = Repo.get!(Node, anchored_node.id).activity_score

    assert Decimal.equal?(worker_score, rebuild_score)
  end

  test "RebuildHotScoresWorker remains rebuildable when dragonfly is unavailable" do
    creator = create_agent!("metrics-dragonfly-outage")

    anchored_node =
      create_node!(creator, %{
        status: :anchored,
        child_count: 3,
        comment_count: 2,
        watcher_count: 1,
        activity_score: Decimal.new("0")
      })

    unavailable_name = :"dragonfly_unavailable_#{System.unique_integer([:positive])}"
    original_name = Application.get_env(:tech_tree, :dragonfly_name)
    original_backend = Application.get_env(:tech_tree, RateLimit, [])

    Application.put_env(:tech_tree, :dragonfly_name, unavailable_name)

    Application.put_env(
      :tech_tree,
      RateLimit,
      Keyword.put(original_backend, :backend, :dragonfly)
    )

    on_exit(fn ->
      restore_application_env(:tech_tree, :dragonfly_name, original_name)
      restore_application_env(:tech_tree, RateLimit, original_backend)
      RateLimit.reset!()
    end)

    assert :ok = RebuildHotScoresWorker.perform(%Job{})

    refreshed = Repo.get!(Node, anchored_node.id)
    assert Decimal.gt?(refreshed.activity_score, Decimal.new("0"))

    assert %{
             canonical_store: :postgres,
             dragonfly_dependency: :none,
             outage_behavior: :fail_open_with_stale_cache_signal,
             rebuildable: true
           } = RebuildHotScoresWorker.policy()

    assert %{
             canonical_store: :postgres,
             dragonfly_dependency: :none,
             outage_behavior: :continue
           } = UpdateMetricsWorker.storage_policy()
  end

  test "IndexCommentWorker recomputes node comment_count idempotently" do
    creator = create_agent!("metrics-comment-creator")
    commenter = create_agent!("metrics-commenter")
    node = create_node!(creator, %{status: :anchored, comment_count: 0})

    comment =
      %TechTree.Comments.Comment{}
      |> TechTree.Comments.Comment.creation_changeset(commenter, node.id, %{
        "body_markdown" => "phase3 comment",
        "body_plaintext" => "phase3 comment"
      })
      |> Repo.insert!()

    args = %{"comment_id" => comment.id}

    assert :ok = IndexCommentWorker.perform(%Job{args: args})
    assert :ok = IndexCommentWorker.perform(%Job{args: args})

    assert Repo.get!(Node, node.id).comment_count == 1
  end

  defp create_agent!(label_prefix) do
    unique = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => "84532",
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

  defp restore_application_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_application_env(app, key, value), do: Application.put_env(app, key, value)
end
