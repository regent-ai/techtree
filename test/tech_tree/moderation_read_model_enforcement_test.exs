defmodule TechTree.ModerationReadModelEnforcementTest do
  use TechTree.DataCase, async: false

  import TechTree.PhaseDApiSupport, only: [create_chatbox_message!: 2]

  alias TechTree.{Accounts, Agents, Comments, Moderation, Nodes, Repo, Search, Chatbox}
  alias TechTree.Comments.Comment
  alias TechTree.Nodes.{Node, NodeTagEdge}

  test "hidden nodes are excluded across public node read paths" do
    admin = create_admin!()
    creator = create_agent!("creator")

    root = create_ready_node!(creator, title: unique_text("root node"))
    child = create_ready_node!(creator, parent_id: root.id, title: unique_text("child node"))
    create_tag_edge!(root.id, child.id)
    :ok = Nodes.refresh_parent_child_metrics!(root.id)

    root_before_hide = Repo.get!(Node, root.id)
    assert root_before_hide.child_count == 1
    assert Decimal.gt?(root_before_hide.activity_score, Decimal.new("0"))

    assert Enum.any?(Nodes.list_public_nodes(%{}), &(&1.id == root.id))
    assert Enum.map(Nodes.list_public_children(root.id, %{}), & &1.id) == [child.id]
    assert Enum.map(Nodes.list_tagged_edges(root.id), & &1.dst_node_id) == [child.id]
    assert Enum.map(Nodes.get_public_node!(root.id).tag_edges_out, & &1.dst_node_id) == [child.id]

    :ok = Moderation.hide_node(child.id, admin, "hidden child")

    root_after_child_hide = Repo.get!(Node, root.id)
    assert root_after_child_hide.child_count == 0
    assert Decimal.equal?(root_after_child_hide.activity_score, Decimal.new("0"))

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
    :ok = Nodes.refresh_comment_metrics!(node.id)

    assert Repo.get!(Node, node.id).comment_count == 2

    assert Enum.map(Comments.list_public_for_node(node.id, %{}), & &1.id) == [
             hidden_comment.id,
             visible_comment.id
           ]

    assert Enum.map(Search.search(hidden_term, %{}).comments, & &1.id) == [hidden_comment.id]

    :ok = Moderation.hide_comment(hidden_comment.id, admin, "hidden comment")

    assert Repo.get!(Node, node.id).comment_count == 1
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

    banned_child =
      create_ready_node!(banned_agent,
        parent_id: active_node.id,
        title: unique_text("banned child")
      )

    banned_comment = create_ready_comment!(active_node.id, banned_agent.id, comment_term)

    _active_comment =
      create_ready_comment!(banned_node.id, active_agent.id, unique_text("active comment"))

    :ok = Nodes.refresh_parent_child_metrics!(active_node.id)
    :ok = Nodes.refresh_comment_metrics!(active_node.id)

    active_node_before_ban = Repo.get!(Node, active_node.id)

    assert active_node_before_ban.child_count == 1
    assert active_node_before_ban.comment_count == 1
    assert Decimal.gt?(active_node_before_ban.activity_score, Decimal.new("0"))

    assert banned_child.parent_id == active_node.id
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

    active_node_after_ban = Repo.get!(Node, active_node.id)

    assert active_node_after_ban.child_count == 0
    assert active_node_after_ban.comment_count == 0
    assert Decimal.equal?(active_node_after_ban.activity_score, Decimal.new("0"))

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

  test "hidden chatbox messages are excluded from public reads" do
    admin = create_admin!()
    author = create_human!("chatbox-hidden-author")

    hidden_message =
      create_chatbox_message!(author, %{body: unique_text("hidden chatbox message")})

    visible_message =
      create_chatbox_message!(author, %{body: unique_text("visible chatbox message")})

    assert Enum.any?(Chatbox.list_public_messages(%{}).messages, &(&1.id == hidden_message.id))
    assert Enum.any?(Chatbox.list_public_messages(%{}).messages, &(&1.id == visible_message.id))

    :ok = Moderation.hide_chatbox_message(hidden_message.id, admin, "hidden message")

    refute Enum.any?(Chatbox.list_public_messages(%{}).messages, &(&1.id == hidden_message.id))
    assert Enum.any?(Chatbox.list_public_messages(%{}).messages, &(&1.id == visible_message.id))
  end

  test "banned human and banned agent chatbox messages are excluded from public reads" do
    admin = create_admin!()

    {:ok, banned_human} =
      Accounts.upsert_human_by_privy_id("human-ban-#{unique_suffix()}", %{
        "wallet_address" => "0xhumanban#{unique_suffix()}",
        "display_name" => "Banned Human",
        "role" => "user"
      })

    banned_agent = create_agent!("chatbox-agent")

    human_message =
      create_chatbox_message!(banned_human, %{body: unique_text("human chatbox msg")})

    agent_message =
      create_chatbox_message!(banned_agent, %{body: unique_text("agent chatbox msg")})

    visible_message =
      create_chatbox_message!(create_human!("chatbox-visible"), %{
        body: unique_text("visible chatbox msg")
      })

    assert Enum.any?(Chatbox.list_public_messages(%{}).messages, &(&1.id == human_message.id))
    assert Enum.any?(Chatbox.list_public_messages(%{}).messages, &(&1.id == agent_message.id))
    assert Enum.any?(Chatbox.list_public_messages(%{}).messages, &(&1.id == visible_message.id))

    :ok = Moderation.ban_human(banned_human.id, admin, "ban human")
    :ok = Moderation.ban_agent(banned_agent.id, admin, "ban agent")

    refute Enum.any?(Chatbox.list_public_messages(%{}).messages, &(&1.id == human_message.id))
    refute Enum.any?(Chatbox.list_public_messages(%{}).messages, &(&1.id == agent_message.id))
    assert Enum.any?(Chatbox.list_public_messages(%{}).messages, &(&1.id == visible_message.id))
  end

  defp create_admin! do
    unique = unique_suffix()

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("admin-#{unique}", %{
        "wallet_address" => "0xadmin#{unique}",
        "display_name" => "Admin #{unique}",
        "role" => "admin"
      })

    human
  end

  defp create_human!(prefix, opts \\ []) do
    unique = unique_suffix()

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("#{prefix}-#{unique}", %{
        "wallet_address" => "0x#{prefix}-wallet-#{unique}",
        "display_name" => Keyword.get(opts, :display_name, "#{prefix}-#{unique}"),
        "role" => Keyword.get(opts, :role, "user")
      })

    human
  end

  defp create_agent!(prefix, status \\ "active") do
    unique = unique_suffix()

    Agents.upsert_verified_agent!(%{
      "chain_id" => "11155111",
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
      status: :anchored,
      parent_id: parent_id,
      publish_idempotency_key: "moderation-node:#{unique}",
      creator_agent_id: creator.id
    })
    |> Repo.insert!()
  end

  defp create_ready_comment!(node_id, author_agent_id, body_plaintext) do
    %Comment{}
    |> Ecto.Changeset.change(%{
      node_id: node_id,
      author_agent_id: author_agent_id,
      body_markdown: body_plaintext,
      body_plaintext: body_plaintext,
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

  defp unique_text(prefix), do: "#{prefix}-#{unique_suffix()}"
  defp unique_suffix, do: System.unique_integer([:positive, :monotonic])
end
