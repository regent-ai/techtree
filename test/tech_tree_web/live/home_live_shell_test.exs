defmodule TechTreeWeb.HomeLiveShellTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the install-first homepage shell with the live tree and right chat pane", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#frontpage-home-page[data-view-mode='graph']")
    assert has_element?(view, "#frontpage-home-page[data-chat-tab='human']")
    assert has_element?(view, "#frontpage-home-page[data-install-agent='openclaw']")
    assert has_element?(view, "#frontpage-regent-shell")
    assert has_element?(view, "#techtree-home-surface")
    assert has_element?(view, "#techtree-home-surface-scene[data-active-face='graph']")
    assert has_element?(view, "#frontpage-node-search")
    assert has_element?(view, "#frontpage-install-panel")
    assert has_element?(view, "#frontpage-install-agent-openclaw[aria-pressed='true']")
    assert has_element?(view, "#frontpage-install-agent-hermes[aria-pressed='false']")
    assert has_element?(view, "#frontpage-install-copy")
    assert has_element?(view, "#frontpage-chat-pane[data-chat-tab='human']")

    assert has_element?(
             view,
             "#frontpage-chat-tab-human[aria-controls='frontpage-human-chatbox']"
           )

    assert has_element?(
             view,
             "#frontpage-chat-tab-agent[aria-controls='frontpage-agent-chatbox']"
           )

    assert has_element?(view, "#frontpage-chat-rail-link")
    assert has_element?(view, "#frontpage-human-chatbox[role='region']:not(.is-hidden)")
    assert has_element?(view, "#frontpage-agent-chatbox[role='region'].is-hidden")
    assert has_element?(view, "#frontpage-human-chat-title")
    assert has_element?(view, "#frontpage-agent-chat-title")
    assert has_element?(view, "#frontpage-branch-paths")
    assert has_element?(view, "#frontpage-bbh-branch")
    refute has_element?(view, "#frontpage-intro-modal")
    assert render(view) =~ "Start TechTree from your terminal"
    assert render(view) =~ "pnpm add -g @regentlabs/cli"
    assert render(view) =~ "regent techtree start"
    assert render(view) =~ "regent techtree bbh run solve ./run --agent openclaw"
    assert render(view) =~ "BBH branch"
    assert render(view) =~ "Jump to the public room panel"
    assert render(view) =~ "Choose your path through the live tree"
  end

  test "homepage starts in light mode", %{conn: conn} do
    html =
      conn
      |> get(~p"/")
      |> html_response(200)

    assert html =~ ~s(data-theme="light")
  end

  test "install agent toggle swaps the copied handoff command without leaving the page", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#frontpage-install-agent-hermes")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-install-agent='hermes']")
    assert has_element?(view, "#frontpage-install-agent-hermes[aria-pressed='true']")
    assert render(view) =~ "regent techtree bbh run solve ./run --agent hermes"
  end

  test "homepage keeps the guided setup framing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert render(view) =~ "TechTree"
    assert render(view) =~ "Start with the guided setup. Let the live tree open below."
    assert render(view) =~ "Tree preview"
    refute render(view) =~ "live mockups"
    refute render(view) =~ "Frontpage Reset"
  end

  test "chat tabs can switch without disturbing the surface", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#frontpage-chat-tab-agent")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-chat-tab='agent']")
    assert has_element?(view, "#frontpage-chat-pane[data-chat-tab='agent']")

    view
    |> element("#frontpage-chat-tab-human")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-chat-tab='human']")
  end
end
