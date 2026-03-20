defmodule TechTreeWeb.FrontpagePlatformE2ETest do
  use TechTreeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TechTree.PlatformFixtures

  test "frontpage and platform core flows stay server-owned end to end", %{conn: conn} do
    agent =
      agent_fixture(%{
        slug: "e2e-agent",
        display_name: "E2E Agent",
        status: "ready",
        feature_tags: ["creator", "relay"]
      })

    explorer_tile_fixture(%{
      coord_key: "0:0",
      x: 0,
      y: 0,
      title: "Origin Tile",
      owner_address: agent.owner_address
    })

    explorer_tile_fixture(%{
      coord_key: "1:0",
      x: 1,
      y: 0,
      title: "Branch Tile",
      metadata: %{"parent_coord_key" => "0:0"}
    })

    {:ok, frontpage, _html} = live(conn, "/")

    frontpage
    |> element("#frontpage-intro-enter")
    |> render_click()

    assert has_element?(frontpage, "#frontpage-home-page[data-intro-open='false']")

    frontpage
    |> element("#frontpage-view-grid")
    |> render_click()

    assert has_element?(frontpage, "#frontpage-home-page[data-view-mode='grid']")
    assert render(frontpage) =~ "Infinite seed lattice"

    {:ok, platform_home, _html} = live(recycle(conn), "/platform")

    assert render(platform_home) =~ "Regent Platform"
    assert render(platform_home) =~ "E2E Agent"

    {:ok, explorer, _html} = live(recycle(conn), "/platform/explorer")

    explorer
    |> element("#platform-tile-0-0")
    |> render_click()

    assert has_element?(explorer, "#platform-explorer-modal")
    assert render(explorer) =~ "Origin Tile"

    explorer
    |> element("#platform-explorer-action-drilldown")
    |> render_click()

    assert has_element?(explorer, "#platform-tile-1-0")
    refute has_element?(explorer, "#platform-tile-0-0")

    {:ok, creator, _html} = live(recycle(conn), "/platform/creator")

    creator
    |> element("button[phx-value-slug='e2e-agent']")
    |> render_click()

    assert render(creator) =~ "E2E Agent"
    assert render(creator) =~ agent.owner_address

    {:ok, agents, _html} = live(recycle(conn), "/platform/agents")

    html =
      agents
      |> form("#platform-agent-filters", filters: %{search: "E2E", status: "ready"})
      |> render_change()

    assert html =~ "E2E Agent"
  end
end
