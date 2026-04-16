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
    assert render(view) =~ "Open the BBH notebook"
    assert render(view) =~ "Check the wall and run page"
    assert render(view) =~ "Practice / Proving / Challenge"
    assert render(view) =~ "marimo-pair over Agent Skills"
    assert render(view) =~ "public BBH loop is working"
    assert render(view) =~ "What the names mean"
    assert render(view) =~ "the public benchmark lane"
    assert render(view) =~ "the scorer and replay check"
    assert render(view) =~ "SkyDiscover"
    assert render(view) =~ "Hypotest"

    assert render(view) =~ "official boards fill in as reviewed runs clear replay"

    assert render(view) =~ "pnpm add -g @regentlabs/cli"
    assert render(view) =~ "regent techtree start"
    assert render(view) =~ "regent techtree bbh run exec --lane climb"
    assert render(view) =~ "npx skills add marimo-team/marimo-pair"
    assert render(view) =~ "uvx deno -A npm:skills add marimo-team/marimo-pair"
    assert render(view) =~ "regent techtree bbh notebook pair ./run"
    assert render(view) =~ "Part 1"
    assert render(view) =~ "Start the workspace"
    assert render(view) =~ "Part 2"
    assert render(view) =~ "Solve locally"
    assert render(view) =~ "Part 3"
    assert render(view) =~ "Publish and prove"
    assert render(view) =~ "regent techtree bbh run solve ./run --solver openclaw"
    assert render(view) =~ "regent techtree bbh run solve ./run --solver hermes"
    assert render(view) =~ "regent techtree bbh run solve ./run --solver skydiscover"
    assert render(view) =~ "regent techtree bbh capsules list --lane climb"
    assert render(view) =~ "regent techtree bbh capsules get &lt;capsule_id&gt;"
    assert render(view) =~ "regent techtree bbh run exec --capsule &lt;capsule_id&gt;"
    assert render(view) =~ "regent techtree bbh submit ./run"
    assert render(view) =~ "regent techtree bbh validate ./run"
    assert render(view) =~ "regent techtree bbh run exec --lane benchmark"
    assert render(view) =~ "Challenge stays public and reviewed"
    assert render(view) =~ "fresh routes land"
    assert render(view) =~ "fills in as verified runs arrive"
    assert render(view) =~ "regent techtree bbh run exec --lane challenge"
  end
end
