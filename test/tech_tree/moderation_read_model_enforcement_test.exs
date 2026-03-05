defmodule TechTree.ModerationReadModelEnforcementTest do
  use TechTree.DataCase, async: false

  alias TechTree.{Accounts, Agents, Comments, Moderation, Nodes, Repo, Search, XMTPMirror}
  alias TechTree.Comments.Comment
  alias TechTree.Nodes.{Node, NodeTagEdge}
  alias TechTree.XMTPMirror.{XmtpMessage, XmtpRoom}

  test "hidden nodes are excluded across public node read paths" do
    admin = create_admin!()
    creator = create_agent!("creator")

    root = create_ready_node!(creator, title: unique_text("root node"))
    child = create_ready_node!(creator, parent_id: root.id, title: unique_text("child node"))
    create_tag_edge!(root.id, child.id)

    assert Enum.any?(Nodes.list_public_nodes(%{}), &(&1.id == root.id))
    assert Enum.map(Nodes.list_public_children(root.id, %{}), & &1.id) == [child.id]
    assert Enum.map(Nodes.list_tagged_edges(root.id), & &1.dst_node_id) == [child.id]
    assert Enum.map(Nodes.get_public_node!(root.id).tag_edges_out, & &1.dst_node_id) == [child.id]

    :ok = Moderation.hide_node(child.id, admin, "hidden child")

    assert Nodes.list_public_children(root.id, %{}) == []
    assert Nodes.list_tagged_edges(root.id) == []
    assert Nodes.get_public_node!(root.id).tag_edges_out == []

    :ok = Moderation.hide_node(root.id, admin, "hidden root")

    refute Enum.any?(Nodes.list_public_nodes(%{}), &(&1.id == root.id))
    assert_raise Ecto.NoResultsError, fn -> Nodes.get_public_node!(root.id) end
    assert Nodes.list_public_children(root.id, %{}) == []
    assert Nodes.list_tagged_edges(root.id) == []
  end

  test "hidden comments are excluded from public comments and search" do
    admin = create_admin!()
    creator = create_agent!("creator")
    commenter = create_agent!("commenter")

    node = create_ready_node!(creator)
    hidden_term = unique_text("hidden comment")
    visible_term = unique_text("visible comment")

    hidden_comment = create_ready_comment!(node.id, commenter.id, hidden_term)
    visible_comment = create_ready_comment!(node.id, commenter.id, visible_term)

    assert Enum.map(Comments.list_public_for_node(node.id, %{}), & &1.id) == [
             hidden_comment.id,
             visible_comment.id
           ]

    assert Enum.map(Search.search(hidden_term, %{}).comments, & &1.id) == [hidden_comment.id]

    :ok = Moderation.hide_comment(hidden_comment.id, admin, "hidden comment")

    assert Enum.map(Comments.list_public_for_node(node.id, %{}), & &1.id) == [visible_comment.id]
    assert Search.search(hidden_term, %{}).comments == []
  end

  test "banned agent content is removed from public node and comment reads" do
    admin = create_admin!()
    banned_agent = create_agent!("banned")
    active_agent = create_agent!("active")

    node_term = unique_text("banned node")
    comment_term = unique_text("banned comment")
    active_node_term = unique_text("active node")

    banned_node = create_ready_node!(banned_agent, title: node_term, seed: "ML")
    active_node = create_ready_node!(active_agent, title: active_node_term, seed: "ML")

    banned_comment = create_ready_comment!(active_node.id, banned_agent.id, comment_term)

    _active_comment =
      create_ready_comment!(banned_node.id, active_agent.id, unique_text("active comment"))

    assert Enum.any?(Nodes.list_public_nodes(%{}), &(&1.id == banned_node.id))
    assert Enum.any?(Nodes.list_hot_nodes("ML", %{}), &(&1.id == banned_node.id))
    assert Nodes.get_public_node!(banned_node.id).id == banned_node.id

    assert Enum.any?(
             Comments.list_public_for_node(active_node.id, %{}),
             &(&1.id == banned_comment.id)
           )

    assert Enum.any?(Comments.list_public_for_node(banned_node.id, %{}))
    assert Enum.any?(Search.search(node_term, %{}).nodes, &(&1.id == banned_node.id))
    assert Enum.any?(Search.search(comment_term, %{}).comments, &(&1.id == banned_comment.id))

    :ok = Moderation.ban_agent(banned_agent.id, admin, "banned agent")

    refute Enum.any?(Nodes.list_public_nodes(%{}), &(&1.id == banned_node.id))
    refute Enum.any?(Nodes.list_hot_nodes("ML", %{}), &(&1.id == banned_node.id))
    assert_raise Ecto.NoResultsError, fn -> Nodes.get_public_node!(banned_node.id) end

    refute Enum.any?(
             Comments.list_public_for_node(active_node.id, %{}),
             &(&1.id == banned_comment.id)
           )

    assert Comments.list_public_for_node(banned_node.id, %{}) == []
    assert Search.search(node_term, %{}).nodes == []
    assert Search.search(comment_term, %{}).comments == []
    assert Enum.any?(Nodes.list_public_nodes(%{}), &(&1.id == active_node.id))
    assert Enum.any?(Search.search(active_node_term, %{}).nodes, &(&1.id == active_node.id))
  end

  test "hidden trollbox messages are excluded from public reads" do
    admin = create_admin!()
    room = create_canonical_room!()
    hidden_message = create_visible_message!(room, unique_text("hidden trollbox message"))
    visible_message = create_visible_message!(room, unique_text("visible trollbox message"))

    assert Enum.any?(XMTPMirror.list_public_messages(%{}), &(&1.id == hidden_message.id))
    assert Enum.any?(XMTPMirror.list_public_messages(%{}), &(&1.id == visible_message.id))

    :ok = Moderation.hide_trollbox_message(hidden_message.id, admin, "hidden message")

    refute Enum.any?(XMTPMirror.list_public_messages(%{}), &(&1.id == hidden_message.id))
    assert Enum.any?(XMTPMirror.list_public_messages(%{}), &(&1.id == visible_message.id))
  end

  test "banned human and banned agent trollbox messages are excluded from public reads" do
    admin = create_admin!()
    room = create_canonical_room!()

    {:ok, banned_human} =
      Accounts.upsert_human_by_privy_id("human-ban-#{unique_suffix()}", %{
        "wallet_address" => "0xhumanban#{unique_suffix()}",
        "xmtp_inbox_id" => "inbox-human-ban-#{unique_suffix()}",
        "display_name" => "Banned Human",
        "role" => "user"
      })

    banned_agent = create_agent!("trollbox-agent")

    human_message = create_message_for_human!(room, banned_human, unique_text("human trollbox msg"))
    agent_message = create_message_for_agent!(room, banned_agent, unique_text("agent trollbox msg"))
    visible_message = create_visible_message!(room, unique_text("visible trollbox msg"))

    assert Enum.any?(XMTPMirror.list_public_messages(%{}), &(&1.id == human_message.id))
    assert Enum.any?(XMTPMirror.list_public_messages(%{}), &(&1.id == agent_message.id))
    assert Enum.any?(XMTPMirror.list_public_messages(%{}), &(&1.id == visible_message.id))

    :ok = Moderation.ban_human(banned_human.id, admin, "ban human")
    :ok = Moderation.ban_agent(banned_agent.id, admin, "ban agent")

    refute Enum.any?(XMTPMirror.list_public_messages(%{}), &(&1.id == human_message.id))
    refute Enum.any?(XMTPMirror.list_public_messages(%{}), &(&1.id == agent_message.id))
    assert Enum.any?(XMTPMirror.list_public_messages(%{}), &(&1.id == visible_message.id))
  end

  defp create_admin! do
    unique = unique_suffix()

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("admin-#{unique}", %{
        "wallet_address" => "0xadmin#{unique}",
        "xmtp_inbox_id" => "inbox-admin-#{unique}",
        "display_name" => "Admin #{unique}",
        "role" => "admin"
      })

    human
  end

  defp create_agent!(prefix, status \\ "active") do
    unique = unique_suffix()

    Agents.upsert_verified_agent!(%{
      "chain_id" => "8453",
      "registry_address" => "0x#{prefix}-registry-#{unique}",
      "token_id" => Integer.to_string(unique),
      "wallet_address" => "0x#{prefix}-wallet-#{unique}",
      "label" => "#{prefix}-#{unique}",
      "status" => status
    })
  end

  defp create_ready_node!(creator, opts \\ []) do
    unique = unique_suffix()
    parent_id = Keyword.get(opts, :parent_id)

    path =
      case parent_id do
        nil -> "n#{unique}"
        id -> "n#{id}.n#{unique}"
      end

    %Node{}
    |> Ecto.Changeset.change(%{
      path: path,
      depth: if(parent_id, do: 1, else: 0),
      seed: Keyword.get(opts, :seed, "ML"),
      kind: Keyword.get(opts, :kind, :hypothesis),
      title: Keyword.get(opts, :title, unique_text("node")),
      notebook_source: "print('node')",
      status: :ready,
      parent_id: parent_id,
      creator_agent_id: creator.id
    })
    |> Repo.insert!()
  end

  defp create_ready_comment!(node_id, author_agent_id, body_plaintext) do
    unique = unique_suffix()

    %Comment{}
    |> Ecto.Changeset.change(%{
      node_id: node_id,
      author_agent_id: author_agent_id,
      body_markdown: body_plaintext,
      body_plaintext: body_plaintext,
      body_cid: "bafy-comment-#{unique}",
      status: :ready
    })
    |> Repo.insert!()
  end

  defp create_tag_edge!(src_node_id, dst_node_id) do
    %NodeTagEdge{}
    |> NodeTagEdge.changeset(%{
      src_node_id: src_node_id,
      dst_node_id: dst_node_id,
      tag: "related",
      ordinal: 1
    })
    |> Repo.insert!()
  end

  defp create_canonical_room! do
    %XmtpRoom{}
    |> XmtpRoom.changeset(%{
      room_key: "public-trollbox",
      name: unique_text("Public Trollbox")
    })
    |> Repo.insert!()
  end

  defp create_visible_message!(room, body) do
    unique = unique_suffix()

    %XmtpMessage{}
    |> XmtpMessage.changeset(%{
      room_id: room.id,
      xmtp_message_id: "msg-#{unique}",
      sender_inbox_id: "inbox-#{unique}",
      sender_type: :human,
      body: body,
      sent_at: DateTime.utc_now(),
      raw_payload: %{},
      moderation_state: "visible"
    })
    |> Repo.insert!()
  end

  defp create_message_for_human!(room, human, body) do
    unique = unique_suffix()

    %XmtpMessage{}
    |> XmtpMessage.changeset(%{
      room_id: room.id,
      xmtp_message_id: "msg-human-#{unique}",
      sender_inbox_id: human.xmtp_inbox_id,
      sender_wallet_address: human.wallet_address,
      sender_type: :human,
      body: body,
      sent_at: DateTime.utc_now(),
      raw_payload: %{},
      moderation_state: "visible"
    })
    |> Repo.insert!()
  end

  defp create_message_for_agent!(room, agent, body) do
    unique = unique_suffix()

    %XmtpMessage{}
    |> XmtpMessage.changeset(%{
      room_id: room.id,
      xmtp_message_id: "msg-agent-#{unique}",
      sender_inbox_id: "agent-inbox-#{unique}",
      sender_wallet_address: agent.wallet_address,
      sender_type: :agent,
      body: body,
      sent_at: DateTime.utc_now(),
      raw_payload: %{},
      moderation_state: "visible"
    })
    |> Repo.insert!()
  end

  defp unique_text(prefix), do: "#{prefix}-#{unique_suffix()}"
  defp unique_suffix, do: System.unique_integer([:positive, :monotonic])
end
