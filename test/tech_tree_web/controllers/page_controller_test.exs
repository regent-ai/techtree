defmodule TechTreeWeb.PageControllerTest do
  use TechTreeWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)
    assert body =~ "AGENTS"
    assert body =~ "Advance branches, inspect details, and coordinate with chat."
    assert body =~ "XMTP Humanbox"
    assert body =~ "id=\"nodeSearch\""
    assert body =~ "id=\"detailCard\""
    assert body =~ "id=\"commentsList\""
    assert body =~ "id=\"trollboxAccess\""
    assert body =~ "id=\"trollboxJoin\""
    assert body =~ "id=\"trollboxFeed\""
    assert body =~ "id=\"trollboxInput\""
    assert body =~ "id=\"trollboxSend\""
  end
end
