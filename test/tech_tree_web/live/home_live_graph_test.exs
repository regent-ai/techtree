defmodule TechTreeWeb.HomeLiveGraphTest do
  use TechTreeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import TechTree.PhaseDApiSupport

  alias TechTree.Nodes

  test "view mode can switch from the graph to the infinite grid", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#frontpage-view-grid")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-view-mode='grid']")
    assert has_element?(view, "#frontpage-home-grid[data-active='true']")
    assert has_element?(view, "#frontpage-home-graph[data-active='false']")

    view
    |> element("#frontpage-view-graph")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-view-mode='graph']")
    assert has_element?(view, "#frontpage-home-grid[data-active='false']")
    assert has_element?(view, "#frontpage-home-graph[data-active='true']")
  end

  test "graph toolbar exposes agent search and highlight controls", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#frontpage-graph-toolbar")
    assert has_element?(view, "#frontpage-graph-agent-search")
    assert has_element?(view, "#frontpage-graph-agent-input")
    assert has_element?(view, "#frontpage-graph-open-palette")
    assert has_element?(view, "#frontpage-graph-mode-chip", "Navigate mode")
    assert has_element?(view, "#frontpage-graph-palette")
    assert has_element?(view, "#frontpage-graph-palette-input")
    assert has_element?(view, "#frontpage-graph-reset-view")
    assert has_element?(view, "#frontpage-toolbar-focus-null")

    view
    |> element("#frontpage-graph-agent-search")
    |> render_change(%{"agent_query" => "no-such-agent"})

    assert render(view) =~ "No agent match yet"
  end

  test "graph payload includes agent wallet addresses when present", %{conn: conn} do
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

    {:ok, view, _html} = live(conn, ~p"/")

    [_, encoded_payload] = Regex.run(~r/data-graph=\"([^\"]+)\"/, render(view))

    payload =
      encoded_payload
      |> String.replace("&quot;", "\"")
      |> String.replace("&#39;", "'")
      |> Jason.decode!()

    wallet_node = Enum.find(payload["nodes"], &(&1["title"] == "wallet signal node"))

    assert wallet_node
    assert wallet_node["agent_wallet_address"] == "0xabc123frontpagewallet"
  end

  test "selected node state survives homepage mode and panel transitions", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    initial_html = render(view)
    selected_node_id = extract_selected_node_id(initial_html)

    target_node_id =
      initial_html
      |> extract_graph_node_ids()
      |> Enum.find(&(&1 != selected_node_id))
      |> case do
        nil -> selected_node_id
        value -> value
      end

    assert is_integer(target_node_id)

    render_hook(view, "select-node", %{"node_id" => target_node_id})

    assert has_element?(view, "#frontpage-home-graph[data-selected-node-id='#{target_node_id}']")
    assert has_element?(view, "#frontpage-home-grid[data-selected-node-id='#{target_node_id}']")

    assert has_element?(
             view,
             "#frontpage-selected-node .badge",
             Integer.to_string(target_node_id)
           )

    view
    |> element("#frontpage-view-grid")
    |> render_click()

    view
    |> element("#frontpage-top-toggle")
    |> render_click()

    view
    |> element("#frontpage-agent-toggle")
    |> render_click()

    assert has_element?(view, "#frontpage-home-page[data-view-mode='grid']")
    assert has_element?(view, "#frontpage-home-page[data-top-open='false']")
    assert has_element?(view, "#frontpage-agent-panel[data-panel-open='false']")
    assert has_element?(view, "#frontpage-home-grid[data-selected-node-id='#{target_node_id}']")

    assert has_element?(
             view,
             "#frontpage-selected-node .badge",
             Integer.to_string(target_node_id)
           )
  end

  defp extract_selected_node_id(html) do
    case Regex.run(~r/data-selected-node-id="(\d+)"/, html, capture: :all_but_first) do
      [value] -> String.to_integer(value)
      _ -> flunk("expected selected node id in rendered homepage html")
    end
  end

  defp extract_graph_node_ids(html) do
    ~r/\\"id\\":(\d+)/
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.map(fn [value] -> String.to_integer(value) end)
    |> Enum.uniq()
  end
end
