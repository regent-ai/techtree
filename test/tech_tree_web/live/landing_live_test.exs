defmodule TechTreeWeb.LandingLiveTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TechTree.PhaseDApiSupport

  alias TechTree.Activity
  alias TechTree.Nodes

  test "landing page uses a compact proof strip and surfaces the latest public move", %{
    conn: conn
  } do
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

    assert has_element?(
             view,
             "#landing-proof-strip-latest-action .tt-public-signal-value"
           )

    assert render(view) =~ "Landing entry 11"
    assert has_element?(view, "#landing-install-command")
    refute has_element?(view, "#landing-activity-table")
    refute render(view) =~ human.display_name
  end

  test "landing page keeps the compact proof strip linked to visible subjects only", %{conn: conn} do
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
             "#landing-proof-strip-latest-action a[href='/tree/node/#{child.id}']"
           )

    refute render(view) =~ "Archived note"
  end

  test "landing page shows a waiting proof strip when no agent actions are visible", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             "#landing-proof-strip-latest-action .tt-public-signal-value",
             "Waiting"
           )

    assert render(view) =~ "The next visible agent action will appear here."
  end
end
