defmodule TechTreeWeb.Human.BranchLiveTest do
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

  test "defaults to branch view", %{conn: conn} do
    _root = seed_with_branches_fixture!()

    {:ok, view, _html} = live(conn, ~p"/tree/seed/ML")

    assert has_element?(view, "#seed-branch-list")
    refute has_element?(view, "#seed-graph-canvas")
  end

  test "toggles to graph view with query param", %{conn: conn} do
    _root = seed_with_branches_fixture!()

    {:ok, view, _html} = live(conn, ~p"/tree/seed/ML")

    view
    |> element("#graph-view-toggle")
    |> render_click()

    assert_patch(view, ~p"/tree/seed/ML?view=graph")
    assert has_element?(view, "#seed-graph-canvas")
    refute has_element?(view, "#seed-branch-list")
  end

  test "renders unknown seed empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tree/seed/not-a-seed")

    assert has_element?(view, "#seed-not-found")
    refute has_element?(view, "#seed-branch-list")
    refute has_element?(view, "#seed-graph-canvas")
  end

  test "renders empty states when known seed has no active branches", %{conn: conn} do
    Repo.delete_all(NodeTagEdge)
    Repo.delete_all(Comment)
    Repo.delete_all(Node)

    {:ok, view, _html} = live(conn, ~p"/tree/seed/ML")

    assert has_element?(view, "#seed-branches .hu-empty")

    view
    |> element("#graph-view-toggle")
    |> render_click()

    assert_patch(view, ~p"/tree/seed/ML?view=graph")
    assert has_element?(view, "#seed-graph .hu-empty")
  end

  test "renders autoskill labels on branch cards", %{conn: conn} do
    node = seed_with_branches_fixture!(:skill)

    Repo.insert!(%NodeBundle{
      node_id: node.id,
      bundle_type: :skill,
      access_mode: :public_free,
      preview_md: "# Preview",
      bundle_manifest: %{"metadata" => %{"version" => "0.1.0"}},
      primary_file: "SKILL.md",
      marimo_entrypoint: "session.marimo.py",
      bundle_uri: "ipfs://bafybranchautoskill",
      bundle_cid: "bafybranchautoskill",
      bundle_hash: "hashbranch"
    })

    {:ok, view, _html} = live(conn, ~p"/tree/seed/ML")

    assert render(view) =~ "Autoskill"
    assert render(view) =~ "Public free"
  end

  test "renders the science tasks branch inside Evals", %{conn: conn} do
    TechTree.ScienceTasks.ensure_public_branch_root!()
    {:ok, view, _html} = live(conn, ~p"/tree/seed/Evals")

    assert render(view) =~ "Science Tasks"
  end

  defp seed_with_branches_fixture!(first_kind \\ :hypothesis) do
    agent = insert_agent_fixture!()
    root = Nodes.create_seed_root!("ML", "Machine Learning")

    node_a =
      insert_ready_node!(agent, root, %{
        title: "Gradient compression",
        summary: "Reduce transfer bandwidth during distributed training.",
        kind: first_kind,
        watcher_count: 5,
        comment_count: 2,
        child_count: 1,
        activity_score: D.new("47.1")
      })

    _node_b =
      insert_ready_node!(agent, root, %{
        title: "Model checkpoint cadence",
        summary: "Balance checkpoint overhead with rollback safety.",
        watcher_count: 2,
        comment_count: 1,
        child_count: 0,
        activity_score: D.new("29.8")
      })

    node_a
  end

  defp insert_agent_fixture! do
    token = System.unique_integer([:positive])
    id = 100_000 + token

    Repo.insert!(%AgentIdentity{
      id: id,
      chain_id: 84_532,
      registry_address: "0x0000000000000000000000000000000000000001",
      token_id: D.new(token),
      wallet_address: "0x00000000000000000000000000000000000000#{rem(token, 90) + 10}",
      label: "test-agent-#{token}",
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
      skill_slug: if(Map.get(attrs, :kind) == :skill, do: "branch-autoskill-#{uniq}", else: nil),
      skill_version: if(Map.get(attrs, :kind) == :skill, do: "0.1.0", else: nil),
      skill_md_body: if(Map.get(attrs, :kind) == :skill, do: "# Preview", else: nil),
      child_count: Map.get(attrs, :child_count, 0),
      comment_count: Map.get(attrs, :comment_count, 0),
      watcher_count: Map.get(attrs, :watcher_count, 0),
      activity_score: Map.get(attrs, :activity_score, D.new("10"))
    })
  end
end
