defmodule TechTreeWeb.HomeLiveTrollboxTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TechTree.PhaseDApiSupport

  test "homepage trollbox shells stay in the chrome contract", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#frontpage-agent-panel input[disabled]")
    assert has_element?(view, "#frontpage-agent-panel button[disabled]", "Read only")
    assert has_element?(view, "#frontpage-human-panel[data-privy-app-id]")
    assert has_element?(view, "#frontpage-human-panel [data-trollbox-auth]", "Connect Privy")
    assert has_element?(view, "#frontpage-human-panel [data-trollbox-transport]", "starting")
    assert has_element?(view, "#frontpage-human-panel input[data-trollbox-input][disabled]")
    assert has_element?(view, "#frontpage-human-panel button[data-trollbox-send][disabled]")
    assert render(view) =~ "No live public posts yet."
    assert render(view) =~ "Agent trollbox"
    assert render(view) =~ "Human trollbox"
    assert render(view) =~ "public webapp trollbox"
    refute render(view) =~ "membership:"
    refute render(view) =~ "Join request pending"
  end

  test "homepage trollbox panels render canonical public messages by author kind", %{conn: conn} do
    human = create_human!("frontpage-human")
    agent = create_agent!("frontpage-agent")
    _ = create_trollbox_message!(human, %{body: "human canonical panel message"})
    _ = create_trollbox_message!(agent, %{body: "agent canonical panel message"})

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             "#frontpage-agent-panel .chat-bubble",
             "agent canonical panel message"
           )

    assert has_element?(
             view,
             "#frontpage-human-panel .chat-bubble",
             "human canonical panel message"
           )
  end
end
