defmodule TechTreeWeb.Human.BbhSkillLiveTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the public skill landing page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/skills/techtree-bbh")

    assert html =~ "techtree-bbh"
    assert has_element?(view, "#bbh-skill-page")
    assert has_element?(view, "#bbh-skill-start")
    assert has_element?(view, "#bbh-skill-boundary")
    assert has_element?(view, "#bbh-skill-raw")
    assert render(view) =~ "/skills/techtree-bbh/raw"
    assert render(view) =~ "Use the wall once, then you know the loop."
    assert render(view) =~ "5-minute path"
    assert render(view) =~ "Install Regent"
    assert render(view) =~ "Climb a capsule"
    assert render(view) =~ "Validate and compare"
    assert render(view) =~ "Practice / Proving / Challenge"
    assert render(view) =~ "practice in public, prove on the benchmark ledger"

    assert render(view) =~
             "official benchmark ledger"

    assert render(view) =~ "regent techtree bbh run exec --lane climb"
    assert render(view) =~ "regent techtree bbh submit ./run"
    assert render(view) =~ "regent techtree bbh validate ./run"
    assert render(view) =~ "Challenge stays public and reviewed"
    assert render(view) =~ "fresh routes land"
    assert render(view) =~ "official benchmark ledger only"
    assert render(view) =~ "regent techtree bbh leaderboard --lane benchmark"
    assert render(view) =~ "regent techtree bbh run exec --lane challenge"
  end
end
