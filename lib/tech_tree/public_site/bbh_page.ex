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
          "Regents CLI sets up the working folder so the notebook, inputs, and evidence stay together."
      },
      %{
        id: "search",
        title: "Search when needed",
        copy:
          "SkyDiscover explores candidate approaches and leaves behind the notes that explain how the search moved."
      },
      %{
        id: "solve",
        title: "Submit the run",
        copy: "The local attempt moves into Techtree so people can compare what worked."
      },
      %{
        id: "replay",
        title: "Check the same result again",
        copy: "Hypotest checks whether the same result still holds when the run is repeated."
      }
    ]
  end
end
