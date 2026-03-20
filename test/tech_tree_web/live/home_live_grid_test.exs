defmodule TechTreeWeb.HomeLiveGridTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "grid node modal gates drilldown and return state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#frontpage-view-grid")
    |> render_click()

    root_node_id = extract_first_grid_node_id(render(view))

    assert has_element?(
             view,
             "#frontpage-home-grid[data-grid-view-depth='0'][data-grid-parent-id='']"
           )

    render_hook(view, "open-grid-node", %{"node_id" => root_node_id})

    assert has_element?(view, "#frontpage-home-grid[data-grid-modal-open='true']")
    assert has_element?(view, "#frontpage-grid-modal")
    assert has_element?(view, "#frontpage-grid-drilldown", "View descendants")

    render_hook(view, "drilldown-grid-node", %{"node_id" => root_node_id})

    assert has_element?(
             view,
             "#frontpage-home-grid[data-grid-view-depth='1'][data-grid-parent-id='#{root_node_id}']"
           )

    assert has_element?(view, "#frontpage-grid-return")
    refute has_element?(view, "#frontpage-home-grid[data-grid-modal-open='true']")

    render_hook(view, "return-grid-level", %{})

    assert has_element?(
             view,
             "#frontpage-home-grid[data-grid-view-depth='0'][data-grid-parent-id='']"
           )

    refute has_element?(view, "#frontpage-grid-return")
  end

  defp extract_first_grid_node_id(html) do
    case Regex.run(~r/data-grid-node-ids="(\d+(?:,\d+)*)"/, html, capture: :all_but_first) do
      [ids] ->
        ids
        |> String.split(",", trim: true)
        |> List.first()
        |> case do
          nil -> flunk("expected at least one grid node id")
          value -> String.to_integer(value)
        end

      _ ->
        flunk("expected grid node ids in rendered homepage html")
    end
  end
end
