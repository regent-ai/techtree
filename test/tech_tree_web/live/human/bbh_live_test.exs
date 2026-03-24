defmodule TechTreeWeb.Human.BbhLiveTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TechTree.BBHFixtures

  test "renders the wall-first leaderboard with separated official strip", %{conn: conn} do
    %{capsule: capsule} =
      BBHFixtures.insert_validated_benchmark_bundle!(%{
        title: "Capsule Alpha",
        label: "wall-leader",
        model_id: "gpt-wall-leader"
      })

    pending_capsule =
      BBHFixtures.insert_capsule!(%{
        split: "climb",
        assignment_policy: "public_next",
        title: "Capsule Beta"
      })

    pending_genome =
      BBHFixtures.insert_genome!(%{label: "pending-runner", model_id: "gpt-pending"})

    BBHFixtures.insert_run!(pending_capsule, pending_genome, %{
      normalized_score: 0.66,
      raw_score: 3.3
    })

    {:ok, view, _html} = live(conn, ~p"/bbh")

    assert has_element?(view, "#bbh-leaderboard-page")
    assert render(view) =~ "Wall board"
    assert has_element?(view, "#bbh-capsule-wall")
    assert has_element?(view, "#bbh-wall-feed")
    assert has_element?(view, "#bbh-wall-drilldown")
    assert has_element?(view, "#bbh-official-strip")
    assert render(view) =~ "Practice"
    assert render(view) =~ "Proving"
    assert render(view) =~ "Challenge"
    assert render(view) =~ "Benchmark ledger"
    assert render(view) =~ "Frontier ticker"
    assert render(view) =~ "--lane climb / benchmark / challenge"
    assert render(view) =~ "public reviewed frontier lane"
    assert render(view) =~ "validated benchmark runs"
    assert has_element?(view, "#bbh-capsule-#{capsule.capsule_id}")
    assert has_element?(view, "#bbh-official-strip")
    assert render(view) =~ "wall-leader"
    refute has_element?(view, "#bbh-official-strip", "pending-runner")
  end

  test "renders seeded published challenge capsules and a separate challenge board", %{conn: conn} do
    %{capsule: seeded_capsule} =
      BBHFixtures.insert_published_challenge_capsule!(%{
        title: "Seeded Frontier Capsule"
      })

    %{run: challenge_run} =
      BBHFixtures.insert_published_challenge_bundle!(%{
        title: "Reviewed Frontier Capsule",
        label: "challenge-runner",
        normalized_score: 0.76,
        raw_score: 3.8
      })

    {:ok, view, _html} = live(conn, ~p"/bbh")

    assert has_element?(view, "#bbh-lane-challenge")
    assert has_element?(view, "#bbh-capsule-#{seeded_capsule.capsule_id}")
    assert render(view) =~ "awaiting first run"
    assert render(view) =~ "reviewed route, waiting for first attempt"
    assert has_element?(view, "#bbh-challenge-strip")
    assert render(view) =~ "Challenge board"
    assert has_element?(view, "#bbh-challenge-official-#{challenge_run.run_id}")
  end

  test "clicking a capsule updates drilldown and survives refresh", %{conn: conn} do
    %{capsule: first_capsule} =
      BBHFixtures.insert_validated_benchmark_bundle!(%{
        title: "Capsule One",
        label: "first-runner",
        model_id: "gpt-first",
        normalized_score: 0.72,
        raw_score: 3.6
      })

    %{capsule: second_capsule} =
      BBHFixtures.insert_validated_benchmark_bundle!(%{
        title: "Capsule Two",
        label: "second-runner",
        model_id: "gpt-second",
        normalized_score: 0.91,
        raw_score: 4.55
      })

    {:ok, view, _html} = live(conn, ~p"/bbh")

    render_click(element(view, "#bbh-capsule-#{second_capsule.capsule_id}"))
    assert_patch(view, ~p"/bbh?#{[focus: second_capsule.capsule_id]}")

    assert has_element?(view, "#bbh-drilldown-#{second_capsule.capsule_id}")
    assert render(view) =~ "Capsule Two"
    assert render(view) =~ "Pinned focus survives refresh"

    send(view.pid, :refresh_board)
    assert render(view) =~ "Capsule Two"
    refute has_element?(view, "#bbh-drilldown-#{first_capsule.capsule_id}")

    {:ok, refreshed_view, _html} =
      live(conn, ~p"/bbh?#{[focus: second_capsule.capsule_id]}")

    assert has_element?(refreshed_view, "#bbh-drilldown-#{second_capsule.capsule_id}")
    refute has_element?(refreshed_view, "#bbh-drilldown-#{first_capsule.capsule_id}")
  end

  test "renders the run page and not found fallback", %{conn: conn} do
    %{run: run, validation: validation, capsule: capsule} =
      BBHFixtures.insert_validated_benchmark_bundle!(%{
        label: "live-run",
        title: "Run Capsule",
        model_id: "gpt-live-run"
      })

    {:ok, view, _html} = live(conn, ~p"/bbh/runs/#{run.run_id}")
    assert has_element?(view, "#bbh-run-page")
    assert has_element?(view, "#bbh-validation-#{validation.validation_id}")
    assert render(view) =~ "Proving lane"
    assert render(view) =~ "official benchmark ledger"
    assert render(view) =~ capsule.title
    assert render(view) =~ "validated"
    assert render(view) =~ "Benchmark ledger boundary"
    assert render(view) =~ "apples-to-apples comparison lane"

    {:ok, missing_view, _html} =
      live(conn, ~p"/bbh/runs/0x9999999999999999999999999999999999999999999999999999999999999999")

    assert render(missing_view) =~ "Run not found"
  end
end
