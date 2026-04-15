defmodule TechTree.BBH.Assignments do
  @moduledoc false

  import Ecto.Query

  alias TechTree.BBH.{Assignment, Capsule, Helpers}
  alias TechTree.Repo

  @climb_split "climb"
  @challenge_split "challenge"
  @draft_split "draft"
  @public_splits [@climb_split, "benchmark", @challenge_split]
  @auto_assignment_policies ["auto", "auto_or_select"]
  @select_assignment_policies ["select", "auto_or_select"]

  def next_assignment(agent_claims, attrs \\ %{}) do
    split = Map.get(attrs, "split", @climb_split)

    with :ok <- ensure_inventory_loaded(),
         true <- split in @public_splits do
      capsule =
        Capsule
        |> where([capsule], capsule.split == ^split)
        |> maybe_limit_to_published_challenges(split)
        |> where([capsule], capsule.assignment_policy in ^@auto_assignment_policies)
        |> order_by([capsule], asc: capsule.inserted_at, asc: capsule.capsule_id)
        |> limit(1)
        |> Repo.one()

      build_assignment_payload(agent_claims, capsule)
    else
      false -> {:error, :invalid_split}
      {:error, reason} -> {:error, reason}
    end
  end

  def select_assignment(agent_claims, attrs) when is_map(attrs) do
    capsule_id = Helpers.required_binary(attrs, "capsule_id")

    with :ok <- ensure_inventory_loaded(),
         {:ok, capsule} <- Helpers.fetch_capsule(capsule_id),
         :ok <- ensure_public_capsule_visible?(capsule),
         :ok <- ensure_capsule_selectable(capsule) do
      build_assignment_payload(agent_claims, capsule)
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  defp ensure_inventory_loaded do
    if Repo.aggregate(Capsule, :count, :capsule_id) > 0 do
      :ok
    else
      {:error, :capsule_inventory_empty}
    end
  end

  defp maybe_limit_to_published_challenges(query, @challenge_split) do
    where(query, [capsule], not is_nil(capsule.published_at))
  end

  defp maybe_limit_to_published_challenges(query, _split), do: query

  defp public_capsule_visible?(%Capsule{split: @draft_split}), do: false
  defp public_capsule_visible?(%Capsule{split: @challenge_split, published_at: nil}), do: false
  defp public_capsule_visible?(%Capsule{}), do: true

  defp ensure_public_capsule_visible?(%Capsule{} = capsule) do
    if public_capsule_visible?(capsule) do
      :ok
    else
      {:error, :capsule_not_found}
    end
  end

  defp ensure_capsule_selectable(%Capsule{assignment_policy: policy})
       when policy in @select_assignment_policies,
       do: :ok

  defp ensure_capsule_selectable(%Capsule{}), do: {:error, :capsule_not_selectable}

  defp build_assignment_payload(_agent_claims, nil), do: {:error, :assignment_not_available}

  defp build_assignment_payload(agent_claims, %Capsule{} = capsule) do
    assignment_ref = "asg_" <> Integer.to_string(System.unique_integer([:positive]), 36)

    attrs = %{
      assignment_ref: assignment_ref,
      capsule_id: capsule.capsule_id,
      split: capsule.split,
      status: "assigned",
      origin: capsule.assignment_policy,
      agent_wallet_address: Map.get(agent_claims, "wallet_address"),
      agent_token_id: Map.get(agent_claims, "token_id")
    }

    with {:ok, assignment} <- %Assignment{} |> Assignment.changeset(attrs) |> Repo.insert() do
      {:ok,
       %{
         assignment_ref: assignment.assignment_ref,
         split: assignment.split,
         capsule: capsule_payload(capsule)
       }}
    end
  end

  defp capsule_payload(capsule) do
    %{
      capsule_id: capsule.capsule_id,
      provider: capsule.provider,
      provider_ref: capsule.provider_ref,
      family_ref: capsule.family_ref,
      instance_ref: capsule.instance_ref,
      split: capsule.split,
      language: capsule.language,
      mode: capsule.mode,
      assignment_policy: capsule.assignment_policy,
      title: capsule.title,
      hypothesis: capsule.hypothesis,
      protocol_md: capsule.protocol_md,
      rubric_json: capsule.rubric_json,
      task_json: capsule.task_json,
      data_files: capsule.data_files,
      artifact_source: capsule.artifact_source,
      publication_artifact_id: capsule.publication_artifact_id,
      publication_review_id: capsule.publication_review_id,
      published_at: capsule.published_at
    }
  end
end
