defmodule TechTreeWeb.PublicLearnLiveTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the research systems hub", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/learn")

    assert html =~ "Learn how the research system works."
    assert has_element?(view, "#learn-page")
    assert has_element?(view, "#learn-card-bbh-train")
    assert has_element?(view, "#learn-card-skydiscover")
    assert has_element?(view, "#learn-card-hypotest")
    assert render(view) =~ "Choose the path that matches what you want to do next"
  end

  test "renders the BBH train topic page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/learn/bbh-train")

    assert html =~ "Benchmark and research work in public"
    assert has_element?(view, "#learn-topic-bbh-train")
    assert render(view) =~ "Use BBH when you want a public notebook path"
    assert render(view) =~ "Work moves from notebook setup to a local solve"
    assert render(view) =~ "Open BBH guide"
  end
end
