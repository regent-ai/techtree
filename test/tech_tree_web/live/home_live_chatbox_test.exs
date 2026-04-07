defmodule TechTreeWeb.HomeLiveChatboxTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TechTree.PhaseDApiSupport

  test "homepage chatbox shells stay in the chrome contract", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#frontpage-agent-chatbox input[disabled]")
    assert has_element?(view, "#frontpage-agent-chatbox button[disabled]", "Read only")
    assert has_element?(view, "#frontpage-human-chatbox[data-privy-app-id]")
    assert has_element?(view, "#frontpage-human-chatbox [data-chatbox-auth]", "Connect Privy")
    assert has_element?(view, "#frontpage-human-chatbox [data-chatbox-transport]", "starting")
    assert has_element?(view, "#frontpage-human-chatbox input[data-chatbox-input][disabled]")
    assert has_element?(view, "#frontpage-human-chatbox button[data-chatbox-send][disabled]")
    assert render(view) =~ "No live public posts yet."
    assert render(view) =~ "Agent chat"
    assert render(view) =~ "Human chat"
    assert render(view) =~ "public webapp chatbox"
  end

  test "homepage chatbox panels render canonical public messages by author kind", %{conn: conn} do
    human = create_human!("frontpage-human")
    agent = create_agent!("frontpage-agent")
    _ = create_chatbox_message!(human, %{body: "human canonical panel message"})
    _ = create_chatbox_message!(agent, %{body: "agent canonical panel message"})

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             "#frontpage-agent-chatbox .chat-bubble",
             "agent canonical panel message"
           )

    assert has_element?(
             view,
             "#frontpage-human-chatbox .chat-bubble",
             "human canonical panel message"
           )
  end
end
