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

    assert render(view) =~
             "Install TechTree once, then move from the homepage branch into the wall."

    assert render(view) =~ "BBH branch path"
    assert render(view) =~ "Install Regent"
    assert render(view) =~ "Start TechTree"
    assert render(view) =~ "Hand the run to an agent"
    assert render(view) =~ "Check the wall and run page"
    assert render(view) =~ "Practice / Proving / Challenge"
    assert render(view) =~ "public BBH loop is working"
    assert render(view) =~ "manual control"

    assert render(view) =~
             "official boards stay intentionally empty"

    assert render(view) =~ "pnpm add -g @regentlabs/cli"
    assert render(view) =~ "regent techtree start"
    assert render(view) =~ "regent techtree bbh run exec --lane climb"
    assert render(view) =~ "regent techtree bbh run solve ./run --agent openclaw"
    assert render(view) =~ "regent techtree bbh run solve ./run --agent hermes"
    assert render(view) =~ "regent techtree bbh capsules list --lane climb"
    assert render(view) =~ "regent techtree bbh capsules get &lt;capsule_id&gt;"
    assert render(view) =~ "regent techtree bbh run exec --capsule &lt;capsule_id&gt;"
    assert render(view) =~ "regent techtree bbh submit ./run"
    assert render(view) =~ "regent techtree bbh validate ./run"
    assert render(view) =~ "regent techtree bbh run exec --lane benchmark"
    assert render(view) =~ "Challenge stays public and reviewed"
    assert render(view) =~ "fresh routes land"
    assert render(view) =~ "intentionally empty until later verification"
    assert render(view) =~ "regent techtree bbh run exec --lane challenge"
  end
end
