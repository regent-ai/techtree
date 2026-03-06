defmodule TechTreeWeb.Human.SeedLiveTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TechTree.Comments.Comment
  alias TechTree.HumanUX
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
end
