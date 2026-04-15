defmodule TechTree.BBH.Inventory do
  @moduledoc false

  alias TechTree.BBH.{Capsule, Helpers}
  alias TechTree.Repo
  alias TechTree.V1.{Artifact, Review}

  @challenge_split "challenge"
  @draft_split "draft"

  def upsert_capsule(attrs) when is_map(attrs) do
    capsule_id = Helpers.required_binary(attrs, "capsule_id")

    %Capsule{}
    |> Capsule.changeset(%{
      capsule_id: capsule_id,
      provider: Helpers.required_binary(attrs, "provider"),
      provider_ref: Helpers.required_binary(attrs, "provider_ref"),
      family_ref: Helpers.optional_binary(attrs, "family_ref"),
      instance_ref: Helpers.optional_binary(attrs, "instance_ref"),
      split: Helpers.required_binary(attrs, "split"),
      language: Map.get(attrs, "language", "python"),
      mode: Map.get(attrs, "mode", Helpers.infer_mode(attrs)),
      assignment_policy: Helpers.required_binary(attrs, "assignment_policy"),
      title: Helpers.required_binary(attrs, "title"),
      hypothesis: Helpers.required_binary(attrs, "hypothesis"),
      protocol_md: Helpers.required_binary(attrs, "protocol_md"),
      rubric_json: Helpers.required_map(attrs, "rubric_json"),
      task_json: Helpers.required_map(attrs, "task_json"),
      data_files: Map.get(attrs, "data_files", []),
      artifact_source: Helpers.optional_map(attrs, "artifact_source") || %{},
      publication_artifact_id: Helpers.optional_binary(attrs, "publication_artifact_id"),
      publication_review_id: Helpers.optional_binary(attrs, "publication_review_id"),
      published_at: Helpers.fetch_value(attrs, "published_at")
    })
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:capsule_id, :inserted_at]},
      conflict_target: :capsule_id
    )
  end

  def promote_challenge_capsule(capsule_id, attrs) when is_binary(capsule_id) and is_map(attrs) do
    artifact_id = Helpers.required_binary(attrs, "publication_artifact_id")
    review_id = Helpers.required_binary(attrs, "publication_review_id")

    assignment_policy =
      Map.get(attrs, "assignment_policy") || Map.get(attrs, :assignment_policy, "auto_or_select")

    with %Capsule{} = capsule <- Repo.get(Capsule, capsule_id),
         true <- capsule.split == @draft_split || {:error, :capsule_not_draft},
         %Artifact{} <- Repo.get(Artifact, artifact_id) || {:error, :artifact_not_found},
         %Review{} = review <- Repo.get(Review, review_id) || {:error, :review_not_found},
         :ok <- validate_challenge_review(review, artifact_id) do
      capsule
      |> Capsule.changeset(%{
        split: @challenge_split,
        assignment_policy: assignment_policy,
        publication_artifact_id: artifact_id,
        publication_review_id: review_id,
        published_at: DateTime.utc_now()
      })
      |> Repo.update()
    else
      nil -> {:error, :capsule_not_found}
      false -> {:error, :capsule_not_draft}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  defp validate_challenge_review(
         %Review{
           kind: "challenge",
           target_type: "artifact",
           target_id: artifact_id,
           result: "confirmed"
         },
         artifact_id
       ),
       do: :ok

  defp validate_challenge_review(_review, _artifact_id), do: {:error, :review_not_publishable}
end
