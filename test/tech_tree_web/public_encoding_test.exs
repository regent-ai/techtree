defmodule TechTreeWeb.PublicEncodingTest do
  use ExUnit.Case, async: true

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Activity.ActivityEvent
  alias TechTree.Comments.Comment
  alias TechTree.Nodes.{Node, NodeTagEdge}
  alias TechTree.Watches.NodeWatcher
  alias TechTreeWeb.PublicEncoding

  test "encode_node converts enums and preloaded associations" do
    creator = %AgentIdentity{id: 10, label: "agent-10", wallet_address: "0xabc"}

    node = %Node{
      id: 7,
      parent_id: nil,
      path: "n7",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "Node 7",
      status: :anchored,
      activity_score: Decimal.new("3.5"),
      comments_locked: false,
      creator_agent: creator,
      tag_edges_out: [%NodeTagEdge{id: 1, src_node_id: 7, dst_node_id: 2, tag: "rel", ordinal: 1}]
    }

    encoded = PublicEncoding.encode_node(node)

    assert encoded.id == 7
    assert encoded.kind == "hypothesis"
    assert encoded.status == "anchored"
    assert encoded.creator_agent == %{id: 10, label: "agent-10", wallet_address: "0xabc"}
    assert encoded.sidelinks == [%{id: 1, src_node_id: 7, dst_node_id: 2, tag: "rel", ordinal: 1}]
  end

  test "encode_search_results encodes node and comment lists" do
    node = %Node{id: 11, kind: :data, status: :anchored, tag_edges_out: []}

    comment = %Comment{
      id: 22,
      node_id: 11,
      author_agent_id: 5,
      body_markdown: "hello",
      body_plaintext: "hello",
      status: :anchored
    }

    encoded = PublicEncoding.encode_search_results(%{nodes: [node], comments: [comment]})

    assert encoded.nodes == [PublicEncoding.encode_node(node)]
    assert encoded.comments == [PublicEncoding.encode_comment(comment)]
  end

  test "encode_watch converts enum fields" do
    watch = %NodeWatcher{id: 3, node_id: 11, watcher_type: :human, watcher_ref: 77}
    assert PublicEncoding.encode_watch(watch).watcher_type == "human"
  end

  test "encode_activity_event includes stream classification" do
    event = %ActivityEvent{
      id: 30,
      actor_type: :agent,
      actor_ref: 10,
      event_type: "economic.reward_earned",
      payload: %{"amount" => "10"}
    }

    encoded = PublicEncoding.encode_activity_event(event)

    assert encoded.stream == "economic"
    assert encoded.event_type == "economic.reward_earned"
  end
end