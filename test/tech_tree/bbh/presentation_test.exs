defmodule TechTree.BBH.PresentationTest do
  use TechTree.DataCase, async: true

  alias TechTree.BBHFixtures
  alias TechTree.BBH.Presentation

  test "leaderboard page separates official ranking from active wall state" do
    confirmed =
      BBHFixtures.insert_validated_benchmark_bundle!(%{
        title: "Confirmed Capsule",
        label: "confirmed-runner",
        model_id: "gpt-confirmed",
        normalized_score: 0.88,
        raw_score: 4.4
      })

    rejected_capsule =
      BBHFixtures.insert_capsule!(%{
        split: "benchmark",
        assignment_policy: "validator_assigned",
        title: "Rejected Capsule"
      })

    rejected_assignment =
      BBHFixtures.insert_assignment!(rejected_capsule, %{origin: "validator_assigned"})

    rejected_genome =
      BBHFixtures.insert_genome!(%{label: "rejected-runner", model_id: "gpt-rejected"})

    rejected_run =
      BBHFixtures.insert_run!(rejected_capsule, rejected_genome, %{
        assignment: rejected_assignment,
        normalized_score: 0.93,
        raw_score: 4.65
      })

    BBHFixtures.insert_validation!(rejected_run, %{result: "rejected"})

    page = Presentation.leaderboard_page(%{split: "benchmark"})

    assert Enum.any?(page.capsules, &(&1.title == "Confirmed Capsule"))
    assert Enum.any?(page.capsules, &(&1.title == "Rejected Capsule"))
    assert Enum.map(page.lane_sections, & &1.label) == ["Practice", "Proving", "Challenge"]

    assert Enum.map(page.lane_sections, & &1.operator_tag) == [
             "--lane climb",
             "--lane benchmark",
             "--lane challenge"
           ]

    assert page.lane_counts.practice + page.lane_counts.proving + page.lane_counts.challenge ==
             length(page.capsules)

    benchmark_board = Enum.find(page.official_boards, &(&1.key == :benchmark))
    challenge_board = Enum.find(page.official_boards, &(&1.key == :challenge))
    assert benchmark_board
    assert challenge_board
    assert Enum.any?(benchmark_board.entries, &(&1.node_id == confirmed.run.run_id))
    refute Enum.any?(benchmark_board.entries, &(&1.display_name == "rejected-runner"))
    assert challenge_board.entries == []
    assert page.drilldown_capsule

    assert page.drilldown_capsule.best_state_label in [
             "validated",
             "self-reported",
             "pending validation"
           ]
  end

  test "selected capsule pins drilldown" do
    first =
      BBHFixtures.insert_validated_benchmark_bundle!(%{
        title: "Capsule A",
        label: "runner-a",
        model_id: "gpt-runner-a",
        normalized_score: 0.61,
        raw_score: 3.05
      })

    second =
      BBHFixtures.insert_validated_benchmark_bundle!(%{
        title: "Capsule B",
        label: "runner-b",
        model_id: "gpt-runner-b",
        normalized_score: 0.97,
        raw_score: 4.85
      })

    page =
      Presentation.leaderboard_page(%{
        split: "benchmark",
        selected_capsule_id: first.capsule.capsule_id
      })

    assert page.selected_capsule_id == first.capsule.capsule_id
    assert page.drilldown_capsule.capsule_id == first.capsule.capsule_id
    assert page.drilldown_capsule.title == "Capsule A"
    assert page.drilldown_capsule.best_state_label in ["validated", "self-reported"]

    assert page.drilldown_capsule.current_best_run.review_state in [
             "validated",
             "pending validation"
           ]

    assert Enum.any?(page.capsules, &(&1.capsule_id == second.capsule.capsule_id))
  end

  test "leaderboard page shows published challenge capsules on the wall before the first run" do
    %{capsule: capsule} =
      BBHFixtures.insert_published_challenge_capsule!(%{
        title: "Seeded Frontier Capsule"
      })

    page = Presentation.leaderboard_page()
    challenge_lane = Enum.find(page.lane_sections, &(&1.key == :challenge))
    challenge_capsule = Enum.find(page.capsules, &(&1.capsule_id == capsule.capsule_id))
    challenge_board = Enum.find(page.official_boards, &(&1.key == :challenge))

    assert challenge_lane
    assert challenge_board
    assert Enum.any?(challenge_lane.capsules, &(&1.capsule_id == capsule.capsule_id))
    assert challenge_capsule.best_score_label == "n/a"
    assert challenge_capsule.best_state_label == "awaiting first run"
    assert challenge_capsule.challenge_status == "reviewed route, waiting for first attempt"
    assert challenge_capsule.challenge_attempts == 0
    assert challenge_capsule.route_maturity == :new
    assert challenge_capsule.active_agent_count == 0
    assert Enum.any?(page.event_feed_items, &(&1.kind == :challenge_revealed))
    assert challenge_board.entries == []
  end

  test "leaderboard page exposes the official challenge board separately from benchmark" do
    %{run: challenge_run} =
      BBHFixtures.insert_published_challenge_bundle!(%{
        title: "Challenge Capsule",
        label: "challenge-runner",
        normalized_score: 0.74,
        raw_score: 3.7
      })

    %{run: benchmark_run} =
      BBHFixtures.insert_validated_benchmark_bundle!(%{
        title: "Benchmark Capsule",
        label: "benchmark-runner",
        model_id: "gpt-benchmark-runner",
        normalized_score: 0.91,
        raw_score: 4.55
      })

    page = Presentation.leaderboard_page()
    benchmark_board = Enum.find(page.official_boards, &(&1.key == :benchmark))
    challenge_board = Enum.find(page.official_boards, &(&1.key == :challenge))

    assert Enum.any?(benchmark_board.entries, &(&1.node_id == benchmark_run.run_id))
    refute Enum.any?(benchmark_board.entries, &(&1.node_id == challenge_run.run_id))
    assert Enum.any?(challenge_board.entries, &(&1.node_id == challenge_run.run_id))
    refute Enum.any?(challenge_board.entries, &(&1.node_id == benchmark_run.run_id))
  end
end
