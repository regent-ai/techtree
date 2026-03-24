defmodule TechTreeWeb.HomeLiveShellTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the homepage shell with intro modal and both trollboxes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#frontpage-home-page[data-intro-open='true']")
    assert has_element?(view, "#frontpage-home-page[data-view-mode='graph']")
    assert has_element?(view, "#frontpage-home-page[data-data-mode='live']")
    assert has_element?(view, "#frontpage-home-graph")
    assert has_element?(view, "#frontpage-home-grid")
    assert has_element?(view, "#frontpage-agent-panel[data-panel-open='true']")
    assert has_element?(view, "#frontpage-human-panel[data-panel-open='true']")
    assert has_element?(view, "#frontpage-agent-panel [data-panel-resize-handle]")
    assert has_element?(view, "#frontpage-human-panel [data-panel-close]")
    assert has_element?(view, "#frontpage-home-briefing")
    refute has_element?(view, "#frontpage-data-live")
    refute has_element?(view, "#frontpage-data-fixture")
    refute has_element?(view, "#frontpage-design-cobalt-orchard")
    refute has_element?(view, "#detailCard")
    refute has_element?(view, "#trollboxAccess")
    refute has_element?(view, "#trollboxJoin")
    refute has_element?(view, "#nodeSearch")
    refute has_element?(view, "#commentsList")
    assert render(view) =~ "Install Regent once"
    assert render(view) =~ "Install in 1 command"
    assert render(view) =~ "Star on GitHub"
    assert has_element?(view, "#frontpage-intro-install")
    assert has_element?(view, "#frontpage-intro-github")
    assert has_element?(view, "#frontpage-intro-bbh-skill")
    assert has_element?(view, "#frontpage-intro-persist")

    assert has_element?(
             view,
             "#frontpage-intro-modal .fp-inline-command",
             "pnpm add -g @regentlabs/cli"
           )
  end

  test "homepage starts in light mode", %{conn: conn} do
    html =
      conn
      |> get(~p"/")
      |> html_response(200)

    assert html =~ ~s(data-theme="light")
  end

  test "enter closes the intro modal without leaving the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#frontpage-intro-enter")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-intro-open='false']")
    assert has_element?(view, "#frontpage-home-graph")
    assert has_element?(view, "#frontpage-home-briefing")
  end

  test "homepage is fixed to the cobalt orchard design", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert render(view) =~ "TechTree Homepage"
    refute render(view) =~ "live mockups"
    refute render(view) =~ "Frontpage Reset"
  end

  test "panels can be collapsed independently", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#frontpage-agent-toggle")
    |> render_click()

    assert has_element?(view, "#frontpage-agent-panel[data-panel-open='false']")
    assert has_element?(view, "#frontpage-human-panel[data-panel-open='true']")

    view
    |> element("#frontpage-human-toggle")
    |> render_click()

    assert has_element?(view, "#frontpage-human-panel[data-panel-open='false']")
  end

  test "top drawer can be collapsed independently from the graph", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#frontpage-top-toggle")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-top-open='false']")
    assert has_element?(view, "#frontpage-home-graph")
  end
end
