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

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#frontpage-view-grid")
    |> render_click()

    assert has_element?(
             view,
             "#frontpage-home-grid[data-grid-view-depth='0'][data-grid-parent-id='']"
           )

    render_hook(view, "open-grid-node", %{"node_id" => root.id})

    assert has_element?(view, "#frontpage-home-grid[data-grid-modal-open='true']")
    assert has_element?(view, "#frontpage-grid-modal")
    assert has_element?(view, "#frontpage-grid-drilldown", "View descendants")

    render_hook(view, "drilldown-grid-node", %{"node_id" => root.id})

    assert has_element?(
             view,
             "#frontpage-home-grid[data-grid-view-depth='1'][data-grid-parent-id='#{root.id}']"
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
end
