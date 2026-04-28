defmodule TechTreeWeb.HomeLiveTerrainTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TechTree.PhaseDApiSupport

  setup do
    agent = create_agent!("home-terrain")
    root = create_ready_node!(agent, seed: "ML", title: "Terrain seed root")
    branch = create_ready_node!(agent, parent_id: root.id, seed: "ML", title: "Terrain branch")

    %{terrain_branch: branch}
  end

  test "terrain selection stays active through mode and chat tab changes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/app")
    %{id: node_id} = first_scene_node(render(view))

    view
    |> element("#techtree-home-surface-scene")
    |> render_hook("regent:node_select", %{
      "target_id" => node_id,
      "face_id" => "graph",
      "meta" => %{"node_id" => node_id, "face_action" => "select-node"}
    })

    assert has_element?(
             view,
             "#techtree-home-surface-scene[data-selected-target-id='#{node_id}']"
           )

    view
    |> element("#frontpage-view-grid")
    |> render_click()

    assert has_element?(view, "#techtree-home-surface-scene[data-active-face='grid']")

    assert has_element?(
             view,
             "#techtree-home-surface-scene[data-selected-target-id='#{node_id}']"
           )

    view
    |> element("#frontpage-chat-tab-agent")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-chat-tab='agent']")

    assert has_element?(
             view,
             "#techtree-home-surface-scene[data-selected-target-id='#{node_id}']"
           )
  end

  test "node search drives focus into the terrain", %{conn: conn, terrain_branch: branch} do
    {:ok, view, _html} = live(conn, ~p"/app")

    view
    |> form("#frontpage-node-search", node_query: branch.title)
    |> render_submit()

    assert has_element?(
             view,
             "#techtree-home-surface-scene[data-selected-target-id='#{branch.id}']"
           )

    assert render(view) =~ branch.title
  end

  test "scene back returns the graph terrain to overview", %{conn: conn, terrain_branch: branch} do
    {:ok, view, _html} = live(conn, ~p"/app")
    node_id = Integer.to_string(branch.id)

    render_hook(view, "select-node", %{"node_id" => node_id})

    assert has_element?(view, "#frontpage-scene-back")
    assert render(view) =~ "Back to overview"

    assert has_element?(
             view,
             "#techtree-home-surface-scene[data-selected-target-id='#{node_id}']"
           )

    view
    |> element("#frontpage-scene-back")
    |> render_click()

    refute has_element?(view, "#frontpage-scene-back")

    refute has_element?(
             view,
             "#techtree-home-surface-scene[data-selected-target-id='#{node_id}']"
           )

    assert has_element?(view, "#techtree-home-surface-scene")
  end

  defp first_scene_node(html) do
    scene_nodes(html)
    |> List.first()
    |> then(fn marker ->
      %{id: marker["id"], label: marker["label"]}
    end)
  end

  defp scene_nodes(html) do
    [encoded] =
      Regex.run(
        ~r/id="techtree-home-surface-scene"[^>]*data-scene-json="([^"]+)"/,
        html,
        capture: :all_but_first
      )

    encoded
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> Jason.decode!()
    |> Map.fetch!("faces")
    |> List.first()
    |> Map.fetch!("markers")
    |> Enum.filter(fn marker ->
      is_binary(marker["id"]) and marker["id"] != "grid:return" and is_binary(marker["label"])
    end)
  end
end
