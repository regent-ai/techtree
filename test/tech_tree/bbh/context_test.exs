defmodule TechTree.BBH.ContextTest do
  use TechTree.DataCase, async: true

  import Ecto.Query

  alias TechTree.BBH
  alias TechTree.BBHFixtures
  alias TechTree.Repo
  alias TechTree.BBH.{Assignment, Capsule}

  test "promote_challenge_capsule publishes a reviewed draft capsule into the challenge lane" do
    %{capsule: capsule, publication_artifact_id: artifact_id, publication_review_id: review_id} =
      BBHFixtures.insert_published_challenge_bundle!(%{title: "Frontier Capsule"})

    published = Repo.get!(Capsule, capsule.capsule_id)

    assert published.split == "challenge"
    assert published.assignment_policy == "auto_or_select"
    assert published.publication_artifact_id == artifact_id
    assert published.publication_review_id == review_id
    assert %DateTime{} = published.published_at
  end

  test "challenge next_assignment ignores unpublished draft capsules" do
    BBHFixtures.insert_capsule!(%{
      split: "draft",
      assignment_policy: "operator",
      provider: "techtree"
    })

    %{capsule: capsule} =
      BBHFixtures.insert_published_challenge_bundle!(%{title: "Published Challenge"})

    assert {:ok, %{split: "challenge", capsule: %{capsule_id: capsule_id}}} =
             BBH.next_assignment(%{}, %{"split" => "challenge"})

    assert capsule_id == capsule.capsule_id
  end

  test "public capsule inventory includes published challenge capsules but not draft ones" do
    BBHFixtures.insert_capsule!(%{
      split: "draft",
      assignment_policy: "operator",
      provider: "techtree",
      title: "Draft Challenge"
    })

    %{capsule: published_capsule} =
      BBHFixtures.insert_published_challenge_capsule!(%{title: "Published Challenge"})

    public_capsules = BBH.list_capsules(%{split: ["climb", "benchmark", "challenge"]})

    assert Enum.any?(public_capsules, &(&1.capsule_id == published_capsule.capsule_id))
    refute Enum.any?(public_capsules, &(&1.title == "Draft Challenge"))
  end

  test "public browse helpers return narrow details and hidden drafts stay hidden" do
    draft_capsule =
      BBHFixtures.insert_capsule!(%{
        split: "draft",
        assignment_policy: "operator",
        provider: "techtree",
        title: "Hidden Draft"
      })

    %{capsule: published_capsule} =
      BBHFixtures.insert_published_challenge_capsule!(%{title: "Browsable Challenge"})

    public_capsules = BBH.list_public_capsules(%{split: ["climb", "benchmark", "challenge"]})

    assert Enum.any?(public_capsules, &(&1.capsule_id == published_capsule.capsule_id))
    refute Enum.any?(public_capsules, &(&1.capsule_id == draft_capsule.capsule_id))

    detail = BBH.get_public_capsule(published_capsule.capsule_id)
    assert detail.capsule_id == published_capsule.capsule_id
    assert detail.task_summary == published_capsule.task_json
    assert Map.has_key?(detail, :rubric_summary)
    assert BBH.get_public_capsule(draft_capsule.capsule_id) == nil
  end

  test "select_assignment creates a new assignment row every time" do
    capsule = BBHFixtures.insert_capsule!(%{split: "climb", assignment_policy: "auto_or_select"})

    assert {:ok, %{assignment_ref: first_ref, capsule: %{capsule_id: capsule_id}}} =
             BBH.select_assignment(%{}, %{"capsule_id" => capsule.capsule_id})

    assert {:ok, %{assignment_ref: second_ref, capsule: %{capsule_id: same_capsule_id}}} =
             BBH.select_assignment(%{}, %{"capsule_id" => capsule.capsule_id})

    assert first_ref != second_ref
    assert capsule_id == capsule.capsule_id
    assert same_capsule_id == capsule.capsule_id

    assert Repo.aggregate(
             from(assignment in Assignment, where: assignment.capsule_id == ^capsule.capsule_id),
             :count,
             :assignment_ref
           ) == 2
  end
end
