defmodule TechTree.AgentInboxTest do
  use TechTree.DataCase, async: true

  alias TechTree.Activity
  alias TechTree.AgentInbox
  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  test "fetch returns a single stream with monotonic next_cursor" do
    agent = create_agent!("inbox")
    other_agent = create_agent!("other")
    agent_node = create_node!(agent)
    other_node = create_node!(other_agent, %{seed: "DeFi"})

    _ = Activity.log!("node.created", :agent, agent.id, agent_node.id, %{seed: "ML"})
    _ = Activity.log!("node.comment_created", :agent, other_agent.id, agent_node.id, %{})
    _ = Activity.log!("economic.reward_earned", :agent, agent.id, nil, %{})
    _ = Activity.log!("node.created", :agent, other_agent.id, other_node.id, %{seed: "DeFi"})

    inbox = AgentInbox.fetch(agent, %{"limit" => "20"})

    assert Enum.map(inbox.events, & &1.event_type) == [
             "node.created",
             "node.comment_created",
             "economic.reward_earned"
           ]

    assert Enum.map(inbox.events, &Activity.classify_stream/1) == [
             :activity,
             :activity,
             :economic
           ]

    assert inbox.next_cursor == Enum.max(Enum.map(inbox.events, & &1.id))

    scoped = AgentInbox.fetch(agent, %{"seed" => "ML"})

    assert Enum.all?(scoped.events, fn event ->
             event.subject_node_id == agent_node.id
           end)

    assert Enum.map(scoped.events, & &1.event_type) == ["node.created", "node.comment_created"]

    new_event = Activity.log!("node.child_created", :agent, other_agent.id, agent_node.id, %{})

    incremental =
      AgentInbox.fetch(agent, %{"cursor" => Integer.to_string(inbox.next_cursor), "limit" => "20"})

    assert Enum.map(incremental.events, & &1.event_type) == ["node.child_created"]
    assert incremental.next_cursor == new_event.id

    empty_poll =
      AgentInbox.fetch(agent, %{
        "cursor" => Integer.to_string(incremental.next_cursor),
        "limit" => "20"
      })

    assert empty_poll.events == []
    assert empty_poll.next_cursor == incremental.next_cursor
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

  defp create_node!(creator, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    base_attrs = %{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "inbox-node-#{unique}",
      status: :anchored,
      notebook_source: "print('node')",
      publish_idempotency_key: "inbox-node:#{unique}",
      creator_agent_id: creator.id
    }

    %Node{}
    |> Ecto.Changeset.change(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end
end
