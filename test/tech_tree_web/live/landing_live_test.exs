defmodule TechTreeWeb.LandingLiveTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TechTree.PhaseDApiSupport

  alias TechTree.Activity
  alias TechTree.Nodes

  test "landing page shows the latest ten agent actions newest first", %{conn: conn} do
    root = Nodes.create_seed_root!("ML", "Machine Learning")
    agent = create_agent!("landing-agent")
    human = create_human!("landing-human")

    nodes =
      for index <- 1..11 do
        create_ready_node!(agent,
          parent_id: root.id,
          seed: "ML",
          title: "Landing entry #{String.pad_leading(Integer.to_string(index), 2, "0")}"
        )
      end

    for {node, index} <- Enum.with_index(nodes, 1) do
      Activity.log!("node.created", :agent, agent.id, node.id, %{
        "node_id" => node.id,
        "seed" => "ML",
        "title" => "Landing entry #{String.pad_leading(Integer.to_string(index), 2, "0")}"
      })
    end

    for index <- 1..80 do
      Activity.log!("node.created", :human, human.id, root.id, %{
        "node_id" => root.id,
        "seed" => "ML",
        "title" => "Human entry #{index}"
      })
    end

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#landing-activity-table-row-1", "Landing entry 11")
    assert has_element?(view, "#landing-activity-table-row-10", "Landing entry 02")
    refute has_element?(view, "#landing-activity-table-row-11")
    refute render(view) =~ "Landing entry 01"
    refute render(view) =~ human.display_name
  end

  test "landing page resolves string node ids and removes broken subject links", %{conn: conn} do
    root = Nodes.create_seed_root!("ML", "Machine Learning")
    agent = create_agent!("landing-link-agent")

    child =
      create_ready_node!(agent,
        parent_id: root.id,
        seed: "ML",
        title: "Resolved child"
      )

    Activity.log!("node.created", :agent, agent.id, nil, %{
      "node_id" => "999999",
      "seed" => "ML",
      "title" => "Archived note"
    })

    Activity.log!("node.child_created", :agent, agent.id, root.id, %{
      "child_node_id" => Integer.to_string(child.id),
      "seed" => "ML",
      "title" => child.title
    })

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             "#landing-activity-table-row-1 a[href='/tree/node/#{child.id}']",
             "Resolved child"
           )

    assert has_element?(
             view,
             "#landing-activity-table-row-2 .tt-public-table-link",
             "Archived note"
           )

    refute has_element?(view, "#landing-activity-table-row-2 a[href='/tree/node/999999']")
  end

  test "landing page shows a plain empty state when no agent actions are visible", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             ".tt-public-empty-state",
             "No public activity is visible yet. The next visible move will appear here."
           )
  end
end
