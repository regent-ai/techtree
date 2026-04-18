defmodule TechTreeWeb.PlatformLiveTest do
  use TechTreeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TechTree.PhaseDApiSupport
  import TechTree.PlatformFixtures

  alias TechTree.Repo
  alias TechTree.Chatbox.Message

  test "platform home renders the main platform shell", %{conn: conn} do
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

  test "explorer keeps the selected tile and drilldown path in the URL", %{conn: conn} do
    explorer_tile_fixture(%{coord_key: "0:0", x: 0, y: 0, title: "Origin Tile"})

    explorer_tile_fixture(%{
      coord_key: "1:0",
      x: 1,
      y: 0,
      title: "Branch Tile",
      metadata: %{"parent_coord_key" => "0:0"}
    })

    {:ok, view, _html} = live(conn, "/platform/explorer")

    assert render(view) =~ "Origin Tile"

    view
    |> element("#platform-tile-0-0")
    |> render_click()

    assert_patch(view, "/platform/explorer?selected=0%3A0")

    view
    |> element("#platform-explorer-action-drilldown")
    |> render_click()

    assert_patch(view, "/platform/explorer?path=0%3A0&selected=1%3A0")

    {:ok, reopened, _html} = live(conn, "/platform/explorer?path=0:0&selected=1:0")

    assert render(reopened) =~ "Branch Tile"
    assert has_element?(reopened, "#platform-tile-1-0")
  end

  test "explorer keeps a shared leaf path instead of collapsing it", %{conn: conn} do
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

    {:ok, reopened, _html} = live(conn, "/platform/explorer?path=0:0,1:0&selected=2:0")

    assert render(reopened) =~ "Leaf Tile"
    assert has_element?(reopened, "#platform-explorer-return")
    assert has_element?(reopened, "#platform-tile-2-0")
    refute has_element?(reopened, "#platform-tile-1-0")
  end

  test "explorer trims a shared leaf path that would otherwise open an empty level", %{conn: conn} do
    explorer_tile_fixture(%{coord_key: "0:0", x: 0, y: 0, title: "Origin Tile"})

    explorer_tile_fixture(%{
      coord_key: "1:0",
      x: 1,
      y: 0,
      title: "Leaf Tile",
      metadata: %{"parent_coord_key" => "0:0"}
    })

    {:ok, reopened, _html} = live(conn, "/platform/explorer?path=0:0,1:0")

    assert render(reopened) =~ "Leaf Tile"
    assert has_element?(reopened, "#platform-tile-1-0")
    refute render(reopened) =~ "Select a tile"
  end

  test "creator prepares a launch packet", %{conn: conn} do
    agent = agent_fixture(%{display_name: "Creator Agent", slug: "creator-agent"})

    {:ok, view, _html} = live(conn, "/platform/creator")

    view
    |> element("button[phx-value-slug='creator-agent']")
    |> render_click()

    assert render(view) =~ "Creator Agent"
    assert render(view) =~ agent.owner_address
    assert has_element?(view, "#platform-creator-hook")
  end

  test "creator keeps the selected agent in the URL", %{conn: conn} do
    agent_fixture(%{display_name: "Creator Agent", slug: "creator-agent"})

    {:ok, view, _html} = live(conn, "/platform/creator")

    view
    |> element("button[phx-value-slug='creator-agent']")
    |> render_click()

    assert_patch(view, "/platform/creator?agent=creator-agent")

    {:ok, reopened, _html} = live(conn, "/platform/creator?agent=creator-agent")

    assert render(reopened) =~ "Creator Agent"
  end

  test "agents index filters results", %{conn: conn} do
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

  test "agents index keeps filters in the URL", %{conn: conn} do
    agent_fixture(%{display_name: "Visible Agent", status: "ready"})
    agent_fixture(%{display_name: "Hidden Agent", status: "failed"})

    {:ok, view, _html} = live(conn, "/platform/agents")

    view
    |> form("#platform-agent-filters", filters: %{search: "Visible", status: "ready"})
    |> render_change()

    assert_patch(view, "/platform/agents?search=Visible&status=ready")

    {:ok, reopened, _html} = live(conn, "/platform/agents?search=Visible&status=ready")

    assert render(reopened) =~ "Visible Agent"
    refute render(reopened) =~ "Hidden Agent"
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

  test "facilitator route renders the facilitator status surface", %{conn: conn} do
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
    message = create_chatbox_message!(author, %{body: "platform moderation live message"})

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
    assert render(view) =~ "hide chatbox_message"
    assert render(view) =~ "unhide chatbox_message"
  end

  test "admin moderation route can ban and restore a message author", %{conn: conn} do
    admin = create_human!("platform-moderation-ban-admin", role: "admin")
    author = create_human!("platform-moderation-ban-author", role: "user")
    message = create_chatbox_message!(author, %{body: "platform moderation author flow"})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{privy_user_id: admin.privy_user_id})
      |> live("/platform/moderation")

    view
    |> element("#moderation-ban-author-#{message.id}")
    |> render_click()

    assert Repo.get!(TechTree.Accounts.HumanUser, author.id).role == "banned"
    assert has_element?(view, "#moderation-unban-author-#{message.id}")

    view
    |> element("#moderation-unban-author-#{message.id}")
    |> render_click()

    assert Repo.get!(TechTree.Accounts.HumanUser, author.id).role == "user"
    assert render(view) =~ "ban human"
    assert render(view) =~ "unban human"
  end

  test "admin moderation route stays live when a message disappears before a click", %{conn: conn} do
    admin = create_human!("platform-moderation-stale-admin", role: "admin")
    author = create_human!("platform-moderation-stale-author", role: "user")
    message = create_chatbox_message!(author, %{body: "platform moderation stale message"})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{privy_user_id: admin.privy_user_id})
      |> live("/platform/moderation")

    Repo.delete!(message)

    view
    |> element("#moderation-hide-message-#{message.id}")
    |> render_click()

    assert render(view) =~ "That item is no longer available."
    refute has_element?(view, "#moderation-hide-message-#{message.id}")
  end

  test "admin moderation route stays live when an author disappears before a click", %{conn: conn} do
    admin = create_human!("platform-moderation-stale-author-admin", role: "admin")
    author = create_human!("platform-moderation-stale-target-author", role: "user")
    message = create_chatbox_message!(author, %{body: "platform moderation stale author"})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{privy_user_id: admin.privy_user_id})
      |> live("/platform/moderation")

    message
    |> Ecto.Changeset.change(
      author_human_id: nil,
      author_display_name_snapshot: author.display_name,
      author_wallet_address_snapshot: author.wallet_address
    )
    |> Repo.update!()

    Repo.delete!(author)

    view
    |> element("#moderation-ban-author-#{message.id}")
    |> render_click()

    assert render(view) =~ "That item is no longer available."
    assert render(view) =~ "platform moderation stale author"
  end

  test "platform flow stays aligned across home, explorer, api, and detail routes", %{
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
