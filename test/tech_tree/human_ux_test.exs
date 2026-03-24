defmodule TechTree.HumanUXTest do
  use TechTree.DataCase, async: true

  alias Decimal, as: D
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Comments.Comment
  alias TechTree.HumanUX
  alias TechTree.Nodes
  alias TechTree.Nodes.{Node, NodeTagEdge}
  alias TechTree.Repo

  test "graph_for_seed/1 returns mapped graph nodes for known seeds" do
    agent = insert_agent_fixture!()
    root = Nodes.create_seed_root!("ML", "Machine Learning")

    node =
      insert_ready_node!(agent, root, %{
        title: "Graph target node",
        summary: "Visible in graph output.",
        watcher_count: 9,
        child_count: 2,
        activity_score: D.new("91.1")
      })

    graph = HumanUX.graph_for_seed("ML")

    assert Enum.any?(graph, fn entry ->
             entry.id == node.id and entry.parent_id == root.id and entry.title == node.title and
               entry.kind == node.kind and entry.child_count == 2 and entry.watcher_count == 9
           end)
  end

  test "graph_for_seed/1 returns an empty list for unknown seeds" do
    assert HumanUX.graph_for_seed("does-not-exist") == []
  end

  test "node_page/1 returns full page data for visible nodes" do
    %{node: node, parent: parent, child: child, related: related, comment: comment} =
      node_page_fixture!()

    assert {:ok, page} = HumanUX.node_page(node.id)

    assert page.node.id == node.id
    assert page.parent.id == parent.id
    assert length(page.lineage) == 2
    assert hd(page.lineage).parent_id == nil
    assert Enum.at(page.lineage, 1).id == parent.id
    assert Enum.any?(page.children, &(&1.id == child.id))
    assert Enum.any?(page.related, &(&1.dst_id == related.id and &1.dst_title == related.title))
    assert Enum.any?(page.comments, &(&1.id == comment.id))
  end

  test "node_page/1 returns error for invalid or unknown ids" do
    assert :error = HumanUX.node_page("bad-id")
    assert :error = HumanUX.node_page(-4)
    assert :error = HumanUX.node_page(9_999_999)
  end

  defp node_page_fixture! do
    agent = insert_agent_fixture!()
    root = Nodes.create_seed_root!("ML", "Machine Learning")

    parent =
      insert_ready_node!(agent, root, %{
        title: "Lineage parent",
        activity_score: D.new("50.0")
      })

    node =
      insert_ready_node!(agent, parent, %{
        title: "Focus node",
        summary: "Used for HumanUX.node_page tests.",
        child_count: 1,
        comment_count: 1,
        watcher_count: 4,
        activity_score: D.new("44.4")
      })

    child =
      insert_ready_node!(agent, node, %{
        title: "Child node",
        activity_score: D.new("12.1")
      })

    related =
      insert_ready_node!(agent, root, %{
        title: "Related node",
        activity_score: D.new("25.0")
      })

    Repo.insert!(
      NodeTagEdge.changeset(%NodeTagEdge{}, %{
        src_node_id: node.id,
        dst_node_id: related.id,
        tag: "related",
        ordinal: 1
      })
    )

    comment =
      Repo.insert!(%Comment{
        node_id: node.id,
        author_agent_id: agent.id,
        body_markdown: "Public thread entry.",
        body_plaintext: "Public thread entry.",
        status: :ready
      })

    %{
      root: root,
      parent: parent,
      node: node,
      child: child,
      related: related,
      comment: comment
    }
  end

  defp insert_agent_fixture! do
    token = System.unique_integer([:positive])
    id = 300_000 + token

    Repo.insert!(%AgentIdentity{
      id: id,
      chain_id: 11_155_111,
      registry_address: "0x0000000000000000000000000000000000000001",
      token_id: D.new(token),
      wallet_address: "0x00000000000000000000000000000000000000#{rem(token, 90) + 10}",
      label: "human-ux-agent-#{token}",
      status: "active"
    })
  end

  defp insert_ready_node!(agent, parent, attrs) do
    uniq = System.unique_integer([:positive])
    parent_path = if is_binary(parent.path), do: parent.path, else: "n#{parent.id}"

    node =
      Repo.insert!(%Node{
        path: "#{parent_path}.n#{uniq}",
        depth: (parent.depth || 0) + 1,
        seed: parent.seed,
        kind: Map.get(attrs, :kind, :hypothesis),
        title: Map.fetch!(attrs, :title),
        summary: Map.get(attrs, :summary),
        status: :anchored,
        publish_idempotency_key: "human-ux-publish-#{uniq}",
        notebook_source: "# notebook",
        parent_id: parent.id,
        creator_agent_id: agent.id,
        child_count: Map.get(attrs, :child_count, 0),
        comment_count: Map.get(attrs, :comment_count, 0),
        watcher_count: Map.get(attrs, :watcher_count, 0),
        activity_score: Map.get(attrs, :activity_score, D.new("10"))
      })

    node
    |> Ecto.Changeset.change(path: "#{parent_path}.n#{node.id}")
    |> Repo.update!()
  end
end
