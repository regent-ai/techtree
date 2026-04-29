defmodule TechTree.BBH.ContextTest do
  use TechTree.DataCase, async: true

  import Ecto.Query

  alias TechTree.BBH
  alias TechTree.BBHFixtures
  alias TechTree.Repo
  alias TechTree.BBH.{Assignment, Capsule, ReviewRequest, Validation}

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

  test "sync_status uses the latest validation for each run across multiple runs" do
    %{run: first_run} = BBHFixtures.insert_validated_benchmark_bundle!()
    %{run: second_run} = BBHFixtures.insert_validated_benchmark_bundle!()

    BBHFixtures.insert_validation!(first_run, %{
      result: "rejected",
      summary: "A later replay rejected the run."
    })

    assert %{runs: runs} = BBH.sync_status([second_run.run_id, first_run.run_id])

    statuses_by_run_id = Map.new(runs, &{&1.run_id, &1})

    assert %{status: "validated", validation_status: "rejected"} =
             Map.fetch!(statuses_by_run_id, first_run.run_id)

    assert %{status: "validated", validation_status: "confirmed"} =
             Map.fetch!(statuses_by_run_id, second_run.run_id)
  end

  test "sync_status prefers database-managed timestamps when validations share the same insert time" do
    %{run: run, validation: first_validation} =
      BBHFixtures.insert_validated_benchmark_bundle!(%{validation_id: "zzz_validation"})

    second_validation =
      BBHFixtures.insert_validation!(run, %{
        validation_id: "aaa_validation",
        result: "rejected",
        summary: "Later review overturned the earlier result."
      })

    inserted_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    updated_at = DateTime.add(inserted_at, 1, :second)

    Repo.update_all(
      from(validation in Validation,
        where: validation.validation_id == ^first_validation.validation_id
      ),
      set: [inserted_at: inserted_at, updated_at: inserted_at]
    )

    Repo.update_all(
      from(validation in Validation,
        where: validation.validation_id == ^second_validation.validation_id
      ),
      set: [inserted_at: inserted_at, updated_at: updated_at]
    )

    assert %{runs: [%{run_id: run_id, validation_status: "rejected"}]} =
             BBH.sync_status([run.run_id])

    assert run_id == run.run_id
  end

  test "ready_draft creates an open review request and review submit activates certificate state" do
    wallet = "0x1111111111111111111111111111111111111111"

    capsule =
      BBHFixtures.insert_capsule!(%{
        split: "draft",
        assignment_policy: "operator",
        provider: "techtree",
        owner_wallet_address: wallet,
        title: "Draft for review"
      })

    reviewer =
      BBHFixtures.insert_reviewer_profile!(%{
        wallet_address: "0x2222222222222222222222222222222222222222",
        vetting_status: "approved"
      })

    assert {:ok, %{capsule: %{workflow_state: "review_ready"}}} =
             BBH.ready_draft(%{"wallet_address" => wallet}, capsule.capsule_id)

    request = Repo.get_by!(ReviewRequest, capsule_id: capsule.capsule_id, state: "open")

    assert {:ok, %{state: "claimed", claimed_by_wallet: claimed_by_wallet}} =
             BBH.claim_review(%{"wallet_address" => reviewer.wallet_address}, request.request_id)

    assert claimed_by_wallet == reviewer.wallet_address

    assert {:ok, %{submission: %{decision: "approve", review_node_id: review_node_id}}} =
             BBH.submit_review(
               %{"wallet_address" => reviewer.wallet_address},
               request.request_id,
               %{
                 "request_id" => request.request_id,
                 "capsule_id" => capsule.capsule_id,
                 "checklist_json" => %{"decision" => "approve"},
                 "suggested_edits_json" => %{"edits" => []},
                 "decision" => "approve",
                 "summary_md" => "Approved."
               }
             )

    updated = Repo.get!(Capsule, capsule.capsule_id)
    assert updated.workflow_state == :approved
    assert updated.certificate_status == :active
    assert updated.certificate_review_id == review_node_id
  end
end
