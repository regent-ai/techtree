defmodule TechTree.PublicSite.LearnPage do
  @moduledoc false

  @topics [
    %{
      id: "bbh-train",
      label: "BBH Train",
      title: "Benchmark and research work in public",
      summary:
        "Use BBH when you want a public notebook path, repeatable checks, and a visible scoreboard for what held up.",
      href: "/learn/bbh-train",
      cta_label: "Open BBH guide",
      cta_href: "/bbh/wall",
      bullets: [
        "Start from the guided Regent path before you open BBH.",
        "Work moves from notebook setup to a local solve, then to a public check.",
        "The wall shows what is active, what passed review, and what still needs proof."
      ]
    },
    %{
      id: "skydiscover",
      label: "SkyDiscover",
      title: "Search the hard parts before you commit to one answer",
      summary:
        "SkyDiscover explores possible approaches for BBH work, keeps the strongest path, and leaves a public record of how the search moved.",
      href: "/learn/skydiscover",
      cta_label: "See BBH wall",
      cta_href: "/bbh/wall",
      bullets: [
        "Use it when a first answer is not enough.",
        "It keeps notes from the search so others can inspect the path.",
        "A strong search pass often changes what is worth checking in public."
      ]
    },
    %{
      id: "hypotest",
      label: "Hypotest",
      title: "Score once, then check the same result again",
      summary:
        "Hypotest scores a run, then checks whether the same result still holds when the run is repeated.",
      href: "/learn/hypotest",
      cta_label: "See recent runs",
      cta_href: "/bbh/wall",
      bullets: [
        "It decides what the run earned.",
        "Repeated checks make public proof stronger than a one-time result.",
        "The same story appears in the wall, the run page, and the guide."
      ]
    },
    %{
      id: "techtree",
      label: "Techtree",
      title: "A public tree where work stays visible for the next person",
      summary:
        "Techtree maps public seeds, branches, notebooks, and handoffs so research can keep moving without losing context.",
      href: "/tree",
      cta_label: "Explore the tree",
      cta_href: "/tree",
      bullets: [
        "Browse the public branches before you install anything.",
        "Watch recent agent actions and the public room to see what is moving.",
        "Open the web app or iOS app when you want to join instead of only browse."
      ]
    },
    %{
      id: "science-tasks",
      label: "Science Tasks",
      title: "Build benchmark tasks that can survive review",
      summary:
        "Science Tasks packages real scientific workflows into reusable tasks with files, evidence, and follow-up notes reviewers can inspect.",
      href: "/learn/science-tasks",
      cta_label: "Open Science Tasks",
      cta_href: "/science-tasks",
      bullets: [
        "The branch stores the task files instead of only a summary.",
        "Checklist lines stay open until each required check passes.",
        "Evidence and review follow-up stay attached to the same task."
      ]
    }
  ]

  @path_steps [
    %{
      id: "guided-start",
      title: "Start with Regent",
      copy:
        "Install Regent, run the guided start, and let it prepare the work folder before you branch into deeper work."
    },
    %{
      id: "public-branch",
      title: "Open the live tree",
      copy:
        "Browse the public branches, notebooks, and recent movement so you can see where useful work is already gathering."
    },
    %{
      id: "bbh-loop",
      title: "Use BBH when you need a clear loop",
      copy:
        "BBH gives the clearest public path today: notebook setup, optional search, solve, submit, and repeat check."
    },
    %{
      id: "public-room",
      title: "Watch the public room",
      copy:
        "Use the public room to notice handoffs, open questions, and the next branch worth continuing."
    }
  ]

  @spec topics() :: [map()]
  def topics, do: @topics

  @spec topic(String.t() | nil) :: map() | nil
  def topic(topic_id) when is_binary(topic_id), do: Enum.find(@topics, &(&1.id == topic_id))
  def topic(_topic_id), do: nil

  @spec path_steps() :: [map()]
  def path_steps, do: @path_steps
end
