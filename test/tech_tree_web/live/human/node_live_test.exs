defmodule TechTreeWeb.Human.NodeLiveTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Decimal, as: D
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Autoskill.NodeBundle
  alias TechTree.Comments.Comment
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Nodes.NodeTagEdge
  alias TechTree.Repo

  test "renders required node sections", %{conn: conn} do
    %{node: node, child: child, related: related, comment: comment, root: root} = node_fixture!()

    {:ok, view, _html} = live(conn, ~p"/node/#{node.id}")

    assert has_element?(view, "#node-hero")
    assert has_element?(view, "#node-proof")
    assert has_element?(view, "#node-lineage")
    assert has_element?(view, "#lineage-node-#{root.id}")
    assert has_element?(view, "#child-node-#{child.id}")
    assert has_element?(view, "#node-impact")
    assert has_element?(view, "#node-discussion")
    assert has_element?(view, "#related-node-#{related.id}-1")
    assert has_element?(view, "#comment-#{comment.id}")
    assert has_element?(view, "#node-monetization-provenance")
    refute has_element?(view, "#node-cross-chain-lineage")
    refute has_element?(view, "#node-graph")
  end

  test "toggles to node graph view", %{conn: conn} do
    %{node: node} = node_fixture!()

    {:ok, view, _html} = live(conn, ~p"/node/#{node.id}")

    view
    |> element("#node-graph-toggle")
    |> render_click()

    assert_patch(view, ~p"/node/#{node.id}?view=graph")
    assert has_element?(view, "#node-graph")
  end

  test "renders not found state when node is missing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/node/999999")

    assert has_element?(view, "#human-node-page")
    assert render(view) =~ "Node not found"
  end

  test "renders not found state for invalid node id", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/node/not-an-id")

    assert has_element?(view, "#human-node-page")
    assert render(view) =~ "Node not found"
  end

  test "renders empty discussion and lineage fallbacks", %{conn: conn} do
    %{node: node} = isolated_node_fixture!()

    {:ok, view, _html} = live(conn, ~p"/node/#{node.id}")

    assert has_element?(view, "#node-lineage .hu-empty")
    assert has_element?(view, "#node-discussion .hu-empty")
  end

  test "renders persisted cross-chain lineage when the backend provides it", %{conn: conn} do
    %{node: node} = isolated_node_fixture!()
    author = Repo.get!(AgentIdentity, node.creator_agent_id)

    target =
      insert_ready_node!(author, Nodes.create_seed_root!("ML", "Machine Learning"), %{
        title: "Mainnet origin",
        summary: "Original version on Ethereum mainnet.",
        activity_score: D.new("2.0"),
        chain_id: 1
      })

    assert {:ok, _link} =
             Nodes.create_or_replace_node_cross_chain_link(node, author, %{
               "relation" => "reproduces",
               "target_chain_id" => 1,
               "target_node_ref" => "eth:mainnet-origin",
               "target_node_id" => target.id,
               "note" => "Published to Base as the lower-cost version."
             })

    {:ok, view, _html} = live(conn, ~p"/node/#{node.id}")

    assert has_element?(view, "#node-cross-chain-lineage")
    assert render(view) =~ "Author claim"
    assert render(view) =~ "Ethereum Mainnet"
  end

  test "renders autoskill panel for bundle-backed nodes", %{conn: conn} do
    %{node: node} = isolated_node_fixture!()

    Repo.insert!(%NodeBundle{
      node_id: node.id,
      bundle_type: :skill,
      access_mode: :public_free,
      preview_md: "# Prompt router\nRoutes tasks cleanly.",
      bundle_manifest: %{"metadata" => %{"version" => "0.1.0"}},
      primary_file: "SKILL.md",
      marimo_entrypoint: "session.marimo.py",
      bundle_uri: "ipfs://bafyautoskill",
      bundle_cid: "bafyautoskill",
      bundle_hash: "abc123def456"
    })

    {:ok, view, _html} = live(conn, ~p"/node/#{node.id}")

    assert has_element?(view, "#node-autoskill")
    assert render(view) =~ "regent techtree autoskill pull #{node.id}"
    assert render(view) =~ "Prompt router"
    assert render(view) =~ "Public free"
  end

  defp node_fixture! do
    agent = insert_agent_fixture!()
    root = Nodes.create_seed_root!("ML", "Machine Learning")

    node =
      insert_ready_node!(agent, root, %{
        title: "Inference budget policy",
        summary: "Choose max token spend by confidence bands.",
        child_count: 1,
        comment_count: 1,
        watcher_count: 3,
        activity_score: D.new("33.2")
      })

    child =
      insert_ready_node!(agent, node, %{
        title: "Latency fallback plan",
        summary: "Fail over to compressed prompts during spikes.",
        activity_score: D.new("11.2")
      })

    related =
      insert_ready_node!(agent, root, %{
        title: "Context packing strategy",
        summary: "Use semantic windows and recency blend.",
        activity_score: D.new("18.0")
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
        body_markdown: "Needs benchmark comparison.",
        body_plaintext: "Needs benchmark comparison.",
        status: :ready
      })

    %{node: node, child: child, related: related, comment: comment, root: root}
  end

  defp isolated_node_fixture! do
    agent = insert_agent_fixture!()
    root = Nodes.create_seed_root!("ML", "Machine Learning")

    node =
      insert_ready_node!(agent, root, %{
        title: "Standalone policy node",
        summary: "No children or related nodes yet.",
        child_count: 0,
        comment_count: 0,
        watcher_count: 0,
        activity_score: D.new("1.0")
      })

    %{node: node}
  end

  defp insert_agent_fixture! do
    token = System.unique_integer([:positive])
    id = 200_000 + token

    Repo.insert!(%AgentIdentity{
      id: id,
      chain_id: 11_155_111,
      registry_address: "0x0000000000000000000000000000000000000001",
      token_id: D.new(token),
      wallet_address: "0x00000000000000000000000000000000000000#{rem(token, 90) + 10}",
      label: "node-test-agent-#{token}",
      status: "active"
    })
  end

  defp insert_ready_node!(agent, parent, attrs) do
    uniq = System.unique_integer([:positive])
    parent_path = if is_binary(parent.path), do: parent.path, else: "n#{parent.id}"

    Repo.insert!(%Node{
      path: "#{parent_path}.n#{uniq}",
      depth: (parent.depth || 0) + 1,
      seed: parent.seed,
      kind: Map.get(attrs, :kind, :hypothesis),
      title: Map.fetch!(attrs, :title),
      summary: Map.get(attrs, :summary),
      status: :anchored,
      publish_idempotency_key: "test-publish-#{uniq}",
      notebook_source: "# notebook",
      parent_id: parent.id,
      creator_agent_id: agent.id,
      child_count: Map.get(attrs, :child_count, 0),
      comment_count: Map.get(attrs, :comment_count, 0),
      watcher_count: Map.get(attrs, :watcher_count, 0),
      activity_score: Map.get(attrs, :activity_score, D.new("10")),
      chain_id: Map.get(attrs, :chain_id)
    })
  end
end
