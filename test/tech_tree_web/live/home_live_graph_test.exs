defmodule TechTreeWeb.HomeLiveGraphTest do
  use TechTreeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TechTree.PhaseDApiSupport

  alias TechTree.Nodes

  test "view mode can switch from the graph to the infinite grid", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/app")

    view
    |> element("#frontpage-view-grid")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-view-mode='grid']")
    assert has_element?(view, "#techtree-home-surface-scene[data-active-face='grid']")
    assert render(view) =~ "Cube field"

    view
    |> element("#frontpage-view-graph")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-view-mode='graph']")
    assert has_element?(view, "#techtree-home-surface-scene[data-active-face='graph']")
    assert render(view) =~ "Live tree observatory"
  end

  test "homepage surface exposes view toggles, node search, and focus reset controls", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/app")

    assert has_element?(view, "#frontpage-view-graph")
    assert has_element?(view, "#frontpage-view-grid")
    assert has_element?(view, "#frontpage-node-search")
    assert has_element?(view, "#frontpage-clear-focus", "Overview")

    assert has_element?(
             view,
             "#techtree-home-ledger",
             "Choose the next branch after the guided start"
           )

    view
    |> form("#frontpage-node-search", node_query: "no-such-node")
    |> render_submit()

    refute has_element?(view, ".fp-terrain-chip-row-search button")
  end

  test "graph agent focus chips include shortened wallet addresses when present", %{conn: conn} do
    root = Nodes.create_seed_root!("ML", "Machine Learning Root")
    agent = create_agent!("frontpage-wallet", wallet_address: "0xabc123frontpagewallet")

    _node =
      create_ready_node!(agent,
        parent_id: root.id,
        seed: "ML",
        title: "wallet signal node",
        watcher_count: 144,
        comment_count: 21,
        activity_score: Decimal.new("999.0")
      )

    {:ok, view, _html} = live(conn, ~p"/app")

    assert render(view) =~ "frontpage-wallet-"
    assert render(view) =~ "0xabc123...llet"
  end

  test "selected node state survives homepage mode and chat tab transitions", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/app")

    initial_html = render(view)

    target_node_id =
      initial_html
      |> extract_graph_node_ids()
      |> Enum.at(1)
      |> case do
        nil -> initial_html |> extract_graph_node_ids() |> List.first()
        value -> value
      end

    assert is_integer(target_node_id)

    render_hook(view, "select-node", %{"node_id" => target_node_id})

    assert has_element?(
             view,
             "#techtree-home-surface-scene[data-selected-target-id='#{target_node_id}']"
           )

    assert has_element?(
             view,
             "#frontpage-selected-node .badge",
             Integer.to_string(target_node_id)
           )

    view
    |> element("#frontpage-view-grid")
    |> render_click()

    view
    |> element("#frontpage-chat-tab-agent")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-view-mode='grid']")
    assert has_element?(view, "#frontpage-home-page[data-chat-tab='agent']")

    assert has_element?(
             view,
             "#techtree-home-surface-scene[data-selected-target-id='#{target_node_id}']"
           )

    assert has_element?(
             view,
             "#frontpage-selected-node .badge",
             Integer.to_string(target_node_id)
           )
  end

  defp extract_graph_node_ids(html) do
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
      is_binary(marker["id"]) and marker["id"] != "grid:return"
    end)
    |> Enum.map(fn marker -> String.to_integer(marker["id"]) end)
    |> Enum.uniq()
  end
end
