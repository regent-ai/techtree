defmodule TechTreeWeb.Human.SeedLiveTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Decimal, as: D
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Comments.Comment
  alias TechTree.HumanUX
  alias TechTree.Autoskill.NodeBundle
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Nodes.NodeTagEdge
  alias TechTree.Repo

  test "defaults to branch-first lanes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/human")

    assert has_element?(view, "#human-seed-page")
    assert has_element?(view, "#seed-branch-overview")
    refute has_element?(view, "#seed-graph-overview")

    for seed <- HumanUX.seed_roots() do
      assert has_element?(view, "#seed-card-#{seed}")
    end
  end

  test "toggles to graph view", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/human")

    view
    |> element("#home-graph-toggle")
    |> render_click()

    assert_patch(view, "/human?view=graph")
    assert has_element?(view, "#seed-graph-overview")
    refute has_element?(view, "#seed-branch-overview")
  end

  test "renders empty states when seeds have no visible graph or branch nodes", %{conn: conn} do
    Repo.delete_all(NodeTagEdge)
    Repo.delete_all(Comment)
    Repo.delete_all(Node)

    {:ok, view, _html} = live(conn, ~p"/human")

    assert has_element?(view, "#seed-branch-overview .hu-empty")

    view
    |> element("#home-graph-toggle")
    |> render_click()

    assert_patch(view, "/human?view=graph")
    assert has_element?(view, "#seed-graph-overview .hu-empty")
  end

  test "shows autoskill labels in seed lanes", %{conn: conn} do
    node = autoskill_seed_node_fixture!()

    Repo.insert!(%NodeBundle{
      node_id: node.id,
      bundle_type: :skill,
      access_mode: :public_free,
      preview_md: "# Preview",
      bundle_manifest: %{"metadata" => %{"version" => "0.1.0"}},
      primary_file: "SKILL.md",
      marimo_entrypoint: "session.marimo.py",
      bundle_uri: "ipfs://bafyseedautoskill",
      bundle_cid: "bafyseedautoskill",
      bundle_hash: "hashseed"
    })

    {:ok, view, _html} = live(conn, ~p"/human")

    assert render(view) =~ "Autoskill"
    assert render(view) =~ "Public free"
  end

  defp autoskill_seed_node_fixture! do
    agent = insert_agent_fixture!()
    root = Nodes.create_seed_root!("Skills", "Skills")
    uniq = System.unique_integer([:positive])

    Repo.insert!(%Node{
      path: "n#{root.id}.n#{uniq}",
      depth: 1,
      seed: "Skills",
      kind: :skill,
      title: "Autoskill seed card",
      summary: "Shown in seed lanes.",
      status: :anchored,
      publish_idempotency_key: "seed-live-autoskill-#{uniq}",
      notebook_source: "# notebook",
      parent_id: root.id,
      creator_agent_id: agent.id,
      skill_slug: "seed-card-skill",
      skill_version: "0.1.0",
      skill_md_body: "# Preview",
      activity_score: D.new("10")
    })
  end

  defp insert_agent_fixture! do
    token = System.unique_integer([:positive])
    wallet_suffix = String.pad_leading(Integer.to_string(rem(token, 999_999), 16), 40, "0")

    Repo.insert!(%AgentIdentity{
      chain_id: 84_532,
      registry_address: "0x0000000000000000000000000000000000000001",
      token_id: D.new(token),
      wallet_address: "0x#{wallet_suffix}",
      label: "seed-live-autoskill-#{token}",
      status: "active"
    })
  end
end
