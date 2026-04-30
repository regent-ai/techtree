defmodule TechTree.PublicSite.LearnPageTest do
  use ExUnit.Case, async: true

  alias TechTree.PublicSite

  @blocked_words [
    "internal architecture",
    "build/runtime",
    "fallback",
    "LiveView",
    "API wiring"
  ]

  test "learn topics stay available through the public site facade" do
    topics = PublicSite.learn_topics()

    assert Enum.map(topics, & &1.id) == [
             "bbh-runs",
             "skydiscover",
             "hypotest",
             "techtree",
             "science-tasks",
             "notebooks",
             "autoskill"
           ]

    assert PublicSite.learn_topic("science-tasks").cta_href == "/science-tasks"
    assert PublicSite.learn_topic("missing") == nil
  end

  test "learn copy uses plain public language" do
    copy =
      PublicSite.learn_topics()
      |> Enum.flat_map(fn topic ->
        [topic.title, topic.summary, topic.cta_label | topic.bullets]
      end)
      |> Enum.concat(Enum.flat_map(PublicSite.learn_path_steps(), &[&1.title, &1.copy]))
      |> Enum.join("\n")

    refute copy =~ "internal jargon"

    for blocked_word <- @blocked_words do
      refute copy =~ blocked_word
    end
  end
end
