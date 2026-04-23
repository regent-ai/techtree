defmodule TechTree.PublicSite.BBHPage do
  @moduledoc false

  alias TechTree.BBH.Presentation

  @spec snapshot() :: map()
  def snapshot do
    page = Presentation.leaderboard_page(%{})

    %{
      lane_counts: page.lane_counts,
      top_score: page.top_score,
      capsules:
        page.lane_sections
        |> Enum.flat_map(& &1.capsules)
        |> Enum.take(6)
        |> Enum.map(fn capsule ->
          %{
            id: capsule.capsule_id,
            title: capsule.title,
            lane: capsule.lane_label,
            status: capsule.best_state_label,
            score_label: capsule.best_score_label,
            freshness: capsule.freshness_label
          }
        end)
    }
  end

  @spec flow_steps() :: [map()]
  def flow_steps do
    [
      %{
        id: "prepare",
        title: "Prepare the run folder",
        copy:
          "Regent sets up the working folder so the next person can see the same story and continue from the same place."
      },
      %{
        id: "search",
        title: "Search when needed",
        copy:
          "SkyDiscover handles the search-heavy cases and leaves behind the notes that explain how the search moved."
      },
      %{
        id: "solve",
        title: "Submit a public run",
        copy:
          "A run moves from local solve into the public board where people can compare what worked."
      },
      %{
        id: "replay",
        title: "Check the same result again",
        copy:
          "Hypotest checks whether the same result still holds when the run is repeated, which makes the proof useful."
      }
    ]
  end
end
