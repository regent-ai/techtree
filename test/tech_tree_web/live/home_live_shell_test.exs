defmodule TechTreeWeb.HomeLiveShellTest do
  use TechTreeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders the install-first homepage shell with the live tree and right chat pane", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/app")

    assert has_element?(view, "#frontpage-home-page[data-view-mode='graph']")
    assert has_element?(view, "#frontpage-home-page[data-chat-tab='human']")
    assert has_element?(view, "#frontpage-home-page[data-install-agent='openclaw']")
    assert has_element?(view, "#frontpage-regent-shell")
    assert has_element?(view, "#frontpage-install-panel")
    assert has_element?(view, "#frontpage-install-agent-openclaw[aria-pressed='true']")
    assert has_element?(view, "#frontpage-install-copy")
    assert has_element?(view, "#frontpage-chat-pane[data-chat-tab='human']")
    assert has_element?(view, "#frontpage-human-chatbox[role='region']:not(.is-hidden)")
    assert has_element?(view, "#frontpage-agent-chatbox[role='region'].is-hidden")
    assert render(view) =~ "regents techtree start"
    assert render(view) =~ "regents techtree bbh run solve ./run --solver openclaw"
  end

  test "homepage starts in light mode", %{conn: conn} do
    html =
      conn
      |> get(~p"/app")
      |> html_response(200)

    assert html =~ ~s(data-theme="light")
  end

  test "homepage leaves the visual background container off by default", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/app")

    refute has_element?(view, "#frontpage-unicorn-hero")
  end

  test "homepage renders the visual background container when enabled", %{conn: conn} do
    with_home_unicorn_hero(
      enabled?: true,
      project_id: "eN0PH49tZnxMuJvuRExK",
      script_url:
        "https://cdn.jsdelivr.net/gh/hiunicornstudio/unicornstudio.js@v2.1.11/dist/unicornStudio.umd.js"
    )

    {:ok, view, _html} = live(conn, ~p"/app")

    assert has_element?(
             view,
             "#frontpage-unicorn-hero[phx-hook='UnicornHero'][phx-update='ignore'][data-us-project='eN0PH49tZnxMuJvuRExK']"
           )
  end

  test "install agent toggle swaps the copied handoff command without leaving the page", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/app")

    view
    |> element("#frontpage-install-agent-hermes")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-install-agent='hermes']")
    assert has_element?(view, "#frontpage-install-agent-hermes[aria-pressed='true']")
    assert render(view) =~ "regents techtree bbh run solve ./run --solver hermes"
  end

  test "chat tabs can switch without disturbing the surface", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/app")

    view
    |> element("#frontpage-chat-tab-agent")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-chat-tab='agent']")
    assert has_element?(view, "#frontpage-chat-pane[data-chat-tab='agent']")
    assert has_element?(view, "#frontpage-agent-chatbox[role='region']:not(.is-hidden)")
    assert has_element?(view, "#frontpage-human-chatbox[role='region'].is-hidden")

    view
    |> element("#frontpage-chat-tab-human")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-chat-tab='human']")
    assert has_element?(view, "#frontpage-human-chatbox[role='region']:not(.is-hidden)")
    assert has_element?(view, "#frontpage-agent-chatbox[role='region'].is-hidden")
  end

  defp with_home_unicorn_hero(config) do
    original = Application.get_env(:tech_tree, :home_unicorn_hero)

    Application.put_env(:tech_tree, :home_unicorn_hero, config)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:tech_tree, :home_unicorn_hero)
        value -> Application.put_env(:tech_tree, :home_unicorn_hero, value)
      end
    end)
  end
end
