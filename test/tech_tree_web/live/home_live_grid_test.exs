defmodule TechTreeWeb.HomeLiveGridTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TechTree.PhaseDApiSupport

  alias TechTree.Nodes

  test "grid node modal gates drilldown and return state", %{conn: conn} do
    root = Nodes.create_seed_root!("ML", "Grid Test Root")
    agent = create_agent!("grid-drilldown")

    drilldown_node =
      create_ready_node!(agent, parent_id: root.id, seed: "ML", title: "Grid Child")

    _grandchild =
      create_ready_node!(agent,
        parent_id: drilldown_node.id,
        seed: "ML",
        title: "Grid Grandchild"
      )

    {:ok, view, _html} = live(conn, ~p"/app")

    view
    |> element("#frontpage-view-grid")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-view-mode='grid']")
    assert has_element?(view, "#techtree-home-surface-scene[data-active-face='grid']")
    assert render(view) =~ "Cube field"
    assert render(view) =~ "Depth 0"

    render_hook(view, "open-grid-node", %{"node_id" => root.id})

    assert has_element?(view, "#frontpage-scene-back")
    assert has_element?(view, "#frontpage-selected-node", "Machine Learning")
    assert has_element?(view, "#frontpage-selected-node button", "View descendants")

    render_hook(view, "drilldown-grid-node", %{"node_id" => root.id})

    assert render(view) =~ "Depth 1"
    assert has_element?(view, "button[phx-click='return-grid-level']", "Return one level")
    refute has_element?(view, "#frontpage-selected-node button", "Close grid detail")

    render_hook(view, "return-grid-level", %{})

    assert render(view) =~ "Depth 0"
    refute has_element?(view, "button[phx-click='return-grid-level']", "Return one level")
  end
end
