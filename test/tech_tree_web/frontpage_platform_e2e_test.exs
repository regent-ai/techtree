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

    {:ok, landing, _html} = live(conn, "/")

    assert has_element?(landing, "#landing-page")
    assert has_element?(landing, "#landing-get-started", "Open Web App")

    assert render(landing) =~
             "A public research tree where agents leave work for the next agent to continue."

    app_redirect =
      landing
      |> element("#landing-get-started")
      |> render_click()

    assert {:error, {:live_redirect, %{to: "/app"}}} = app_redirect

    {:ok, frontpage, _html} = follow_redirect(app_redirect, conn, "/app")

    assert has_element?(frontpage, "#frontpage-home-page[data-install-agent='openclaw']")
    assert has_element?(frontpage, "#frontpage-home-page[data-chat-tab='human']")

    frontpage
    |> element("#frontpage-view-grid")
    |> render_click()

    assert has_element?(frontpage, "#frontpage-home-page[data-view-mode='grid']")
    assert render(frontpage) =~ "Infinite seed lattice"
    assert render(frontpage) =~ "Homepage rooms"
    assert has_element?(frontpage, "#frontpage-chat-rail-link", "Jump to the public rooms")

    {:ok, platform_home, _html} = live(conn, "/platform")

    assert render(platform_home) =~ "Regent Platform"
    assert render(platform_home) =~ "E2E Agent"

    explorer_redirect =
      platform_home
      |> element(
        "a[href='/platform/explorer']",
        "Use Explorer when you need the current frontier layout and drilldown path."
      )
      |> render_click()

    assert {:error, {:live_redirect, %{to: "/platform/explorer"}}} = explorer_redirect

    {:ok, explorer, _html} = follow_redirect(explorer_redirect, conn, "/platform/explorer")

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

    creator_redirect =
      explorer
      |> element("a[href='/platform/creator']")
      |> render_click()

    assert {:error, {:live_redirect, %{to: "/platform/creator"}}} = creator_redirect

    {:ok, creator, _html} = follow_redirect(creator_redirect, conn, "/platform/creator")

    creator
    |> element("button[phx-value-slug='e2e-agent']")
    |> render_click()

    assert render(creator) =~ "E2E Agent"
    assert render(creator) =~ agent.owner_address

    {:ok, agents, _html} = live(conn, "/platform/agents")

    html =
      agents
      |> form("#platform-agent-filters", filters: %{search: "E2E", status: "ready"})
      |> render_change()

    assert html =~ "E2E Agent"
  end
end
