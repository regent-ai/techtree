defmodule TechTreeWeb.PageControllerTest do
  use TechTreeWeb.ConnCase

  test "GET / renders the landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ ~s(id="frontpage-home-page")
    assert body =~ ~s(id="frontpage-regent-shell")
    assert body =~ ~s(id="techtree-home-surface")
    assert body =~ ~s(id="techtree-home-chamber")
    assert body =~ ~s(id="frontpage-chat-pane")
    assert body =~ ~s(id="frontpage-human-chatbox")
    assert body =~ ~s(id="frontpage-agent-chatbox")
    assert body =~ "Start TechTree once, then move through the next branch with the same story."
    assert body =~ "pnpm add -g @regentlabs/cli"
    assert body =~ "regent techtree start"
    assert body =~ "regent techtree bbh run solve ./run --solver openclaw"
    assert body =~ "What opens next"
    assert body =~ "Connect wallet"
    assert body =~ "Choose the next branch after the guided start"
    assert body =~ "BBH branch"
    assert body =~ "SkyDiscover"
    assert body =~ "Hypotest"
    assert body =~ "Platform and rooms"
  end

  test "GET / renders configured Privy app id", %{conn: conn} do
    original_privy = Application.get_env(:tech_tree, :privy)

    on_exit(fn ->
      if is_nil(original_privy) do
        Application.delete_env(:tech_tree, :privy)
      else
        Application.put_env(:tech_tree, :privy, original_privy)
      end
    end)

    Application.put_env(:tech_tree, :privy, app_id: "privy-app-test-id")

    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ ~s(data-privy-app-id="privy-app-test-id")
  end

  test "GET / falls back to empty Privy app id when unset", %{conn: conn} do
    original_privy = Application.get_env(:tech_tree, :privy)

    on_exit(fn ->
      if is_nil(original_privy) do
        Application.delete_env(:tech_tree, :privy)
      else
        Application.put_env(:tech_tree, :privy, original_privy)
      end
    end)

    Application.delete_env(:tech_tree, :privy)

    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ ~s(data-privy-app-id="")
  end

  test "GET /skill.md serves the hosted techtree skill", %{conn: conn} do
    conn = get(conn, "/skill.md")
    body = response(conn, 200)

    assert body =~ "name: techtree"
    assert body =~ "# Techtree"
    assert body =~ "regent techtree start"
    assert body =~ "BBH is the Big-Bench Hard branch in TechTree."
    assert body =~ "SkyDiscover is the search runner."
    assert body =~ "Hypotest is the scorer and replay check."
    assert body =~ "github.com/regent-ai/techtree/tree/main/regent-cli"
  end
end
