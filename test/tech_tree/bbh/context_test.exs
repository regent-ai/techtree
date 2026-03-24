defmodule TechTree.BBH.ContextTest do
  use TechTree.DataCase, async: true

  alias TechTree.BBH
  alias TechTree.BBHFixtures
  alias TechTree.Repo
  alias TechTree.BBH.Capsule

  test "promote_challenge_capsule publishes a reviewed draft capsule into the challenge lane" do
    %{capsule: capsule, publication_artifact_id: artifact_id, publication_review_id: review_id} =
      BBHFixtures.insert_published_challenge_bundle!(%{title: "Frontier Capsule"})

    published = Repo.get!(Capsule, capsule.capsule_id)

    assert published.split == "challenge"
    assert published.assignment_policy == "operator_assigned"
    assert published.publication_artifact_id == artifact_id
    assert published.publication_review_id == review_id
    assert %DateTime{} = published.published_at
  end

  test "challenge next_assignment ignores unpublished draft capsules" do
    BBHFixtures.insert_capsule!(%{
      split: "draft",
      assignment_policy: "draft_only",
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
      assignment_policy: "draft_only",
      provider: "techtree",
      title: "Draft Challenge"
    })

    %{capsule: published_capsule} =
      BBHFixtures.insert_published_challenge_capsule!(%{title: "Published Challenge"})

    public_capsules = BBH.list_capsules(%{split: ["climb", "benchmark", "challenge"]})

    assert Enum.any?(public_capsules, &(&1.capsule_id == published_capsule.capsule_id))
    refute Enum.any?(public_capsules, &(&1.title == "Draft Challenge"))
  end
end
