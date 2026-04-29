defmodule TechTree.WorkersWatcherFanoutTest do
  use TechTree.DataCase, async: false

  @fanout_event [:tech_tree, :watches, :fanout]
  @fanout_worker_event [:tech_tree, :workers, :fanout_watcher_notifications, :stop]

  alias Oban.Job
  alias Phoenix.PubSub
  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Repo
  alias TechTree.Watches
  alias TechTree.Workers.FanoutWatcherNotificationsWorker

  test "fanout_node_activity broadcasts stable payload on watcher node topics" do
    creator = create_agent!("fanout")
    node = create_node!(creator)
    node_id = node.id

    {:ok, _human_watch} = Watches.watch_human(node_id, 101)
    {:ok, _agent_watch} = Watches.watch_agent(node_id, 202)

    :ok = PubSub.subscribe(TechTree.PubSub, watcher_node_topic(:human, 101, node_id))
    :ok = PubSub.subscribe(TechTree.PubSub, watcher_node_topic(:agent, 202, node_id))

    assert :ok = Watches.fanout_node_activity(node_id)

    assert_receive human_payload
    assert_receive agent_payload

    expected_human_payload = %{
      event: "node_activity",
      node_id: node_id,
      watcher_type: "human",
      watcher_ref: 101
    }

    expected_agent_payload = %{
      event: "node_activity",
      node_id: node_id,
      watcher_type: "agent",
      watcher_ref: 202
    }

    assert [human_payload, agent_payload] |> MapSet.new() ==
             [expected_human_payload, expected_agent_payload] |> MapSet.new()
  end

  test "FanoutWatcherNotificationsWorker uses fanout flow and supports string node ids" do
    creator = create_agent!("worker-fanout")
    node = create_node!(creator)
    node_id = node.id

    worker_handler_id = "fanout-worker-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        worker_handler_id,
        @fanout_worker_event,
        fn event, measurements, metadata, pid ->
          send(pid, {:fanout_worker_telemetry, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(worker_handler_id) end)

    {:ok, _watch} = Watches.watch_human(node_id, 303)
    :ok = PubSub.subscribe(TechTree.PubSub, watcher_node_topic(:human, 303, node_id))

    assert :ok =
             FanoutWatcherNotificationsWorker.perform(%Job{
               args: %{"node_id" => Integer.to_string(node_id)}
             })

    assert_receive payload

    assert payload == %{
             event: "node_activity",
             node_id: node_id,
             watcher_type: "human",
             watcher_ref: 303
           }

    assert_receive {:fanout_worker_telemetry, @fanout_worker_event, %{duration: duration},
                    metadata}

    assert duration > 0
    assert metadata.node_id == node_id
  end

  test "fanout_node_activity emits telemetry with stable counts" do
    creator = create_agent!("fanout-telemetry")
    node = create_node!(creator)
    node_id = node.id

    {:ok, _human_watch} = Watches.watch_human(node_id, 901)
    {:ok, _agent_watch} = Watches.watch_agent(node_id, 902)

    handler_id = "watch-fanout-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        @fanout_event,
        fn event, measurements, metadata, pid ->
          send(pid, {:fanout_telemetry, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok = Watches.fanout_node_activity(node_id)

    assert_receive {:fanout_telemetry, @fanout_event, measurements, metadata}
    assert metadata.node_id == node_id
    assert metadata.outcome == "ok"
    assert measurements.watchers == 2
    assert measurements.online_sessions >= 0
    assert measurements.watcher_broadcasts == 2
    assert measurements.session_broadcasts >= 0
  end

  test "fanout also targets online session topics from local cache" do
    creator = create_agent!("cache-online")
    node = create_node!(creator)
    node_id = node.id
    session_id = "sess-#{System.unique_integer([:positive])}"
    online_key = "watch:online:#{node_id}"

    assert {:ok, _} = Cachex.del(:techtree_cache, online_key)
    {:ok, _watch} = Watches.watch_human(node_id, 404)
    assert :ok = Watches.add_online_session(node_id, session_id)

    :ok = PubSub.subscribe(TechTree.PubSub, watcher_node_topic(:human, 404, node_id))
    :ok = PubSub.subscribe(TechTree.PubSub, online_session_topic(session_id))

    assert :ok = Watches.fanout_node_activity(node_id)

    assert_receive watcher_payload
    assert_receive session_payload

    expected_payload = %{
      event: "node_activity",
      node_id: node_id,
      watcher_type: "human",
      watcher_ref: 404
    }

    assert watcher_payload == expected_payload
    assert session_payload == expected_payload

    assert :ok = Watches.remove_online_session(node_id, session_id)
    assert {:ok, _} = Cachex.del(:techtree_cache, online_key)
  end

  test "fanout_node_activity returns :ok when node has no watchers" do
    creator = create_agent!("no-watchers")
    node = create_node!(creator)

    assert :ok = Watches.fanout_node_activity(node.id)
    refute_receive _, 25
  end

  defp watcher_node_topic(watcher_type, watcher_ref, node_id) do
    "watcher:#{watcher_type}:#{watcher_ref}:node:#{node_id}"
  end

  defp online_session_topic(session_id) do
    "watch:session:#{session_id}"
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

  defp create_node!(creator, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    base_attrs = %{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "watcher-node-#{unique}",
      status: :pinned,
      notebook_source: "print('node')",
      publish_idempotency_key: "watcher-node:#{unique}",
      creator_agent_id: creator.id
    }

    %Node{}
    |> Ecto.Changeset.change(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end
end
