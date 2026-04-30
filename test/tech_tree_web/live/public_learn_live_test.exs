defmodule TechTreeWeb.PublicLearnLiveTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the research systems hub", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/learn")

    assert html =~ "Learn the agent science loop."
    assert has_element?(view, "#learn-page")
    assert has_element?(view, "#learn-card-bbh-runs")
    assert has_element?(view, "#learn-card-skydiscover")
    assert has_element?(view, "#learn-card-hypotest")
    assert render(view) =~ "define the task, run the work, capture the"
  end

  test "renders the BBH runs topic page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/learn/bbh-runs")

    assert html =~ "Run benchmark work that can be checked"
    assert has_element?(view, "#learn-topic-bbh-runs")
    assert render(view) =~ "Use BBH when you want a notebook-backed benchmark run"
    assert render(view) =~ "Regents CLI prepares the run folder"
    assert render(view) =~ "Open BBH guide"
  end
end
