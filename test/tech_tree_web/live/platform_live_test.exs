defmodule TechTreeWeb.PlatformLiveTest do
  use TechTreeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TechTree.PhaseDApiSupport
  import TechTree.PlatformFixtures

  alias TechTree.Repo
  alias TechTree.Trollbox.Message

  test "platform home renders the cutover shell", %{conn: conn} do
    agent_fixture(%{display_name: "Home Agent"})
    explorer_tile_fixture(%{coord_key: "0:0", x: 0, y: 0})

    {:ok, view, _html} = live(conn, "/platform")

    assert has_element?(view, "#platform-home-scene")
    assert render(view) =~ "Regent Platform"
    assert render(view) =~ "Home Agent"
  end

  test "explorer opens a modal and drills down through descendants", %{conn: conn} do
    explorer_tile_fixture(%{coord_key: "0:0", x: 0, y: 0, title: "Origin Tile"})

    explorer_tile_fixture(%{
      coord_key: "1:0",
      x: 1,
      y: 0,
      title: "Branch Tile",
      metadata: %{"parent_coord_key" => "0:0"}
    })

    explorer_tile_fixture(%{
      coord_key: "2:0",
      x: 2,
      y: 0,
      title: "Leaf Tile",
      metadata: %{"parent_coord_key" => "1:0"}
    })

    {:ok, view, _html} = live(conn, "/platform/explorer")

    assert has_element?(view, "#platform-tile-0-0")
    refute has_element?(view, "#platform-explorer-return")

    view
    |> element("#platform-tile-0-0")
    |> render_click()

    assert has_element?(view, "#platform-explorer-modal")
    assert render(view) =~ "Origin Tile"

    view
    |> element("#platform-explorer-action-drilldown")
    |> render_click()

    assert has_element?(view, "#platform-explorer-return")
    assert has_element?(view, "#platform-tile-1-0")
    refute has_element?(view, "#platform-tile-0-0")

    view
    |> element("#platform-tile-1-0")
    |> render_click()

    assert render(view) =~ "Branch Tile"

    view
    |> element("#platform-explorer-action-drilldown")
    |> render_click()

    assert has_element?(view, "#platform-tile-2-0")
    refute has_element?(view, "#platform-tile-1-0")

    view
    |> element("#platform-explorer-return")
    |> render_click()

    assert has_element?(view, "#platform-tile-1-0")
  end

  test "creator prepares a launch packet without leaving LiveView", %{conn: conn} do
    agent = agent_fixture(%{display_name: "Creator Agent", slug: "creator-agent"})

    {:ok, view, _html} = live(conn, "/platform/creator")

    view
    |> element("button[phx-value-slug='creator-agent']")
    |> render_click()

    assert render(view) =~ "Creator Agent"
    assert render(view) =~ agent.owner_address
    assert has_element?(view, "#platform-creator-hook")
  end

  test "agents index filters results server-side", %{conn: conn} do
    agent_fixture(%{display_name: "Visible Agent", status: "ready"})
    agent_fixture(%{display_name: "Hidden Agent", status: "failed"})

    {:ok, view, _html} = live(conn, "/platform/agents")

    html =
      view
      |> form("#platform-agent-filters", filters: %{search: "Visible", status: "ready"})
      |> render_change()

    assert html =~ "Visible Agent"
    refute html =~ "Hidden Agent"
  end

  test "agent detail renders imported metadata", %{conn: conn} do
    agent =
      agent_fixture(%{
        slug: "detail-agent",
        display_name: "Detail Agent",
        status: "ready",
        feature_tags: ["creator", "relay"]
      })

    {:ok, view, _html} = live(conn, "/platform/agents/#{agent.slug}")

    assert render(view) =~ "Detail Agent"
    assert render(view) =~ "creator, relay"
  end

  test "facilitator route renders the Phoenix-native probe shell", %{conn: conn} do
    previous = System.get_env("FACILITATOR_API_BASE_URL")

    on_exit(fn ->
      if previous do
        System.put_env("FACILITATOR_API_BASE_URL", previous)
      else
        System.delete_env("FACILITATOR_API_BASE_URL")
      end
    end)

    System.delete_env("FACILITATOR_API_BASE_URL")

    {:ok, view, _html} = live(conn, "/platform/facilitator")

    assert render(view) =~ "No Facilitator base URL is configured for this environment."
  end

  test "names and redeem routes render imported rows", %{conn: conn} do
    name_claim_fixture(%{fqdn: "alpha.agent.ethereum.eth"})
    basename_mint_allowance_fixture(%{address: "0xallowance"})

    basename_payment_credit_fixture(%{
      address: "0xcredit",
      payment_tx_hash: "0x" <> String.duplicate("2", 64)
    })

    ens_subname_claim_fixture(%{fqdn: "ens.agent.ethereum.eth"})
    redeem_claim_fixture(%{source_collection: "Genesis Badge"})

    {:ok, names_view, _html} = live(conn, "/platform/names")
    {:ok, redeem_view, _html} = live(conn, "/platform/redeem")

    assert render(names_view) =~ "alpha.agent.ethereum.eth"
    assert render(names_view) =~ "Credits, allowances, and ENS claims"
    assert render(names_view) =~ "ens.agent.ethereum.eth"
    assert has_element?(names_view, "#platform-names-hook")
    assert render(redeem_view) =~ "Genesis Badge"
  end

  test "moderation route requires an admin platform session", %{conn: conn} do
    human = create_human!("platform-moderation-user", role: "user")

    assert {:error, {:redirect, %{to: "/platform", flash: %{"error" => "Admin required"}}}} =
             conn
             |> init_test_session(%{privy_user_id: human.privy_user_id})
             |> live("/platform/moderation")
  end

  test "admin moderation route renders the queue and can hide and restore a message", %{
    conn: conn
  } do
    admin = create_human!("platform-moderation-admin", role: "admin")
    author = create_human!("platform-moderation-author", role: "user")
    message = create_trollbox_message!(author, %{body: "platform moderation live message"})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{privy_user_id: admin.privy_user_id})
      |> live("/platform/moderation")

    assert has_element?(view, "#platform-moderation-scene")
    assert render(view) =~ "platform moderation live message"

    view
    |> element("#moderation-hide-message-#{message.id}")
    |> render_click()

    assert Repo.get!(Message, message.id).moderation_state == "hidden"
    assert has_element?(view, "#moderation-unhide-message-#{message.id}")

    view
    |> element("#moderation-unhide-message-#{message.id}")
    |> render_click()

    assert Repo.get!(Message, message.id).moderation_state == "visible"
    assert render(view) =~ "hide trollbox_message"
    assert render(view) =~ "unhide trollbox_message"
  end

  test "platform cutover flow stays aligned across home, explorer, api, and detail routes", %{
    conn: conn
  } do
    agent =
      agent_fixture(%{
        slug: "atlas-regent",
        display_name: "Atlas Regent",
        status: "ready",
        owner_address: "0x1234567890123456789012345678901234567890",
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
      title: "Child Tile",
      owner_address: agent.owner_address,
      metadata: %{"parent_coord_key" => "0:0"}
    })

    name_claim_fixture(%{fqdn: "atlas.agent.ethereum.eth", owner_address: agent.owner_address})

    redeem_claim_fixture(%{
      wallet_address: agent.owner_address,
      source_collection: "Atlas Genesis"
    })

    {:ok, home_view, _html} = live(conn, "/platform")
    {:ok, explorer_view, _html} = live(conn, "/platform/explorer")
    {:ok, detail_view, _html} = live(conn, "/platform/agents/#{agent.slug}")

    assert render(home_view) =~ "Atlas Regent"
    assert has_element?(home_view, "a[href='/platform/agents/#{agent.slug}']")

    explorer_view
    |> element("#platform-tile-0-0")
    |> render_click()

    assert has_element?(explorer_view, "#platform-explorer-modal")
    assert render(explorer_view) =~ "Origin Tile"

    explorer_view
    |> element("#platform-explorer-action-drilldown")
    |> render_click()

    assert has_element?(explorer_view, "#platform-tile-1-0")
    assert render(detail_view) =~ agent.owner_address
    assert render(detail_view) =~ "creator, relay"

    assert %{"tiles" => tiles} =
             conn
             |> recycle()
             |> get("/api/platform/explorer/tiles")
             |> json_response(200)

    assert Enum.any?(tiles, &(&1["coord_key"] == "0:0" and &1["child_count"] == 1))
    assert Enum.any?(tiles, &(&1["coord_key"] == "1:0" and &1["parent_coord_key"] == "0:0"))
  end
end
