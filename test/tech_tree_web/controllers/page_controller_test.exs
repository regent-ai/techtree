defmodule TechTreeWeb.PageControllerTest do
  use TechTreeWeb.ConnCase

  test "GET / renders the landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ "tt-landing-root"
    assert body =~ ~s(phx-hook="LandingHero")
    assert body =~ "Signal Room"
    assert body =~ ~s(id="nodeSearch")
    assert body =~ ~s(id="tt-chat-drawer-toggle")
    assert body =~ ~s(id="detailCard")
    assert body =~ ~s(id="commentsList")
    assert body =~ ~s(id="trollboxAccess")
    assert body =~ ~s(id="trollboxJoin")
    assert body =~ ~s(id="trollboxFeed")
    assert body =~ ~s(id="trollboxInput")
    assert body =~ ~s(id="trollboxSend")
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
end
