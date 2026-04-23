defmodule TechTree.BBH.WallCopy do
  @moduledoc false

  def page_copy do
    %{
      header_subtitle:
        "Follow BBH by lane, keep one capsule pinned, and see which runs held up in replay.",
      hero_kicker: "BBH wall branch",
      hero_title: "Use the wall when you want a closer read on one BBH branch.",
      hero_notes: [
        "Practice is public climb work, Proving is benchmark work, and Challenge is the reviewed frontier lane.",
        "Stay here when you want lane pressure, a pinned capsule, and a clear read on which runs used notebook work, which used SkyDiscover search, and which held up under Hypotest replay."
      ],
      caption_chips: [
        "Practice lane",
        "Proving lane",
        "Challenge lane",
        "Pick one capsule to pin",
        "Pinned capsule stays selected"
      ],
      pinned_note: "The pinned capsule stays selected while new wall activity appears around it."
    }
  end

  def lane_sections(capsules) do
    capsules_by_lane = Enum.group_by(capsules, & &1.lane_key)

    [
      lane_section(
        :practice,
        "Practice",
        "--lane climb",
        "Public climb work. Use this lane to improve an approach in the open before it moves toward proof.",
        capsules_by_lane[:practice] || []
      ),
      lane_section(
        :proving,
        "Proving",
        "--lane benchmark",
        "Public benchmark work. Use this lane to see which approaches are ready for replay and comparison.",
        capsules_by_lane[:proving] || []
      ),
      lane_section(
        :challenge,
        "Challenge",
        "--lane challenge",
        "Reviewed frontier work. Use this lane to inspect published challenge capsules and the replay results attached to them.",
        capsules_by_lane[:challenge] || []
      )
    ]
  end

  def official_board_specs do
    [
      %{
        key: :benchmark,
        title: "Benchmark ledger",
        intro_kicker: "Replay-backed benchmark work",
        intro_note: "The benchmark ledger shows confirmed replay results from the Proving lane.",
        empty_message: "No benchmark ledger entries are visible yet."
      },
      %{
        key: :challenge,
        title: "Challenge board",
        intro_kicker: "Reviewed frontier work",
        intro_note:
          "The challenge board shows reviewed challenge capsules after a confirmed replay result.",
        empty_message: "No challenge board entries are visible yet."
      }
    ]
  end

  defp lane_section(key, label, operator_tag, copy, capsules) do
    %{
      key: key,
      label: label,
      operator_tag: operator_tag,
      copy: copy,
      count: length(capsules),
      capsules: capsules
    }
  end
end
