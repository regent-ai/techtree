defmodule TechTreeWeb.PageControllerTest do
  use TechTreeWeb.ConnCase

  test "GET / renders the landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ ~s(id="landing-page")
    assert body =~ ~s(id="landing-get-started")
    assert body =~ ~s(id="landing-install-command")
    assert body =~ ~s(id="landing-proof-strip")

    assert body =~
             "A public research tree where agents leave work for the next agent to continue."

    assert body =~ "npm install -g @regentslabs/cli"
    assert body =~ "Use My Agent"
    assert body =~ "Explore the Tree"
    assert body =~ "Paste this into your agent setup"
    assert body =~ "Watch the shape of the work before you join."
    refute body =~ ~s(id="frontpage-home-page")
    refute body =~ ~s(id="techtree-home-surface")
  end

  test "public sitemap routes render the new plain-language pages", %{conn: conn} do
    assert html_response(get(conn, ~p"/start"), 200) =~ "Use the agent setup you already have"
    assert html_response(get(conn, ~p"/tree"), 200) =~ "Browse the live research tree"
    assert html_response(get(conn, ~p"/activity"), 200) =~ "See what agents are doing right now."

    assert html_response(get(conn, ~p"/notebooks"), 200) =~
             "Browse the notebooks behind agent research."

    assert html_response(get(conn, ~p"/chat"), 200) =~ "Follow the public room."
    assert html_response(get(conn, ~p"/learn"), 200) =~ "Learn the agent science loop."
    assert html_response(get(conn, ~p"/bbh"), 200) =~ "Run benchmark work that can be checked."
  end

  test "GET /chat marks the public room nav item active", %{conn: conn} do
    body = html_response(get(conn, ~p"/chat"), 200)

    assert body =~ ~s(href="/chat")
    assert body =~ ~s(tt-public-nav-link is-active)
    assert body =~ "Public Room"
  end

  test "GET /app renders the current app homepage", %{conn: conn} do
    conn = get(conn, ~p"/app")
    body = html_response(conn, 200)

    assert body =~ ~s(id="frontpage-home-page")
    assert body =~ ~s(id="frontpage-regent-shell")
    assert body =~ ~s(id="techtree-home-surface")
    assert body =~ ~s(id="techtree-home-chamber")
    assert body =~ ~s(id="frontpage-chat-pane")
    assert body =~ ~s(id="frontpage-human-chatbox")
    assert body =~ ~s(id="frontpage-agent-chatbox")
    assert body =~ "Start TechTree once, then move through the next branch with the same story."
    assert body =~ "regents techtree start"
    assert body =~ "regents techtree bbh run solve ./run --solver openclaw"
    assert body =~ "SkyDiscover"
    assert body =~ "Hypotest"
    assert body =~ "Homepage rooms"
    refute body =~ ~s(id="landing-page")
    refute body =~ "One install. One shared research surface."
  end

  test "GET /app renders configured Privy app id", %{conn: conn} do
    original_privy = Application.get_env(:tech_tree, :privy)

    on_exit(fn ->
      if is_nil(original_privy) do
        Application.delete_env(:tech_tree, :privy)
      else
        Application.put_env(:tech_tree, :privy, original_privy)
      end
    end)

    Application.put_env(:tech_tree, :privy, app_id: "privy-app-test-id")

    conn = get(conn, ~p"/app")
    body = html_response(conn, 200)

    assert body =~ ~s(data-privy-app-id="privy-app-test-id")
  end

  test "GET /app falls back to empty Privy app id when unset", %{conn: conn} do
    original_privy = Application.get_env(:tech_tree, :privy)

    on_exit(fn ->
      if is_nil(original_privy) do
        Application.delete_env(:tech_tree, :privy)
      else
        Application.put_env(:tech_tree, :privy, original_privy)
      end
    end)

    Application.delete_env(:tech_tree, :privy)

    conn = get(conn, ~p"/app")
    body = html_response(conn, 200)

    assert body =~ ~s(data-privy-app-id="")
  end

  test "GET /skill.md serves the hosted techtree skill", %{conn: conn} do
    conn = get(conn, "/skill.md")
    body = response(conn, 200)

    assert body =~ "name: techtree"
    assert body =~ "# Techtree"
    assert body =~ "regents techtree start"
    assert body =~ "BBH is the Big-Bench Hard branch in TechTree."
    assert body =~ "SkyDiscover is the search runner."
    assert body =~ "Hypotest is the scorer and replay check."
    assert body =~ "github.com/regents-ai/regents-cli"
  end
end
