defmodule TechTree.BBH.Drafts do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias TechTree.BBH.{Capsule, DraftProposal, Helpers, ReviewRequest, ReviewSubmission}
  alias TechTree.Repo

  @draft_split "draft"
  @review_open_states [:open, :claimed]

  def create_draft(agent_claims, attrs) when is_map(attrs) do
    wallet = Helpers.required_wallet(agent_claims)
    title = Helpers.required_binary(attrs, "title")
    workspace = Helpers.required_map(attrs, "workspace")
    capsule_id = Helpers.draft_capsule_id()

    %Capsule{}
    |> Capsule.changeset(%{
      capsule_id: capsule_id,
      provider: "techtree",
      provider_ref: "draft/#{capsule_id}",
      family_ref: Helpers.optional_binary(attrs, "seed"),
      instance_ref: capsule_id,
      split: @draft_split,
      language: "python",
      mode: "fixed",
      assignment_policy: "operator",
      title: title,
      hypothesis: workspace_hypothesis(workspace),
      protocol_md: Helpers.required_binary(workspace, "protocol_md"),
      rubric_json: Helpers.required_map(workspace, "rubric_json"),
      task_json: Helpers.required_map(workspace, "capsule_source"),
      data_files: [],
      artifact_source: %{},
      owner_wallet_address: wallet,
      source_node_id: Helpers.fetch_value(attrs, "source_node_id"),
      seed: Helpers.optional_binary(attrs, "seed"),
      parent_id: Helpers.fetch_value(attrs, "parent_id"),
      workflow_state: :authoring,
      notebook_py: Helpers.required_binary(workspace, "notebook_py"),
      capsule_source: Helpers.required_map(workspace, "capsule_source"),
      recommended_genome_source:
        Helpers.optional_map(workspace, "recommended_genome_source") || %{},
      genome_notes_md: Helpers.optional_binary(workspace, "genome_notes_md"),
      certificate_status: :none
    })
    |> Repo.insert()
    |> case do
      {:ok, capsule} ->
        {:ok,
         %{capsule: draft_capsule_payload(capsule), workspace: draft_workspace_payload(capsule)}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def list_drafts(agent_claims) do
    wallet = Helpers.required_wallet(agent_claims)

    {:ok,
     Capsule
     |> where(
       [capsule],
       capsule.split == @draft_split and capsule.owner_wallet_address == ^wallet
     )
     |> order_by([capsule], asc: capsule.inserted_at)
     |> Repo.all()
     |> Enum.map(&draft_capsule_payload/1)}
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def get_draft(capsule_id) when is_binary(capsule_id) do
    with {:ok, capsule} <- Helpers.fetch_capsule(capsule_id),
         true <- capsule.split == @draft_split || {:error, :capsule_not_found} do
      {:ok,
       %{capsule: draft_capsule_payload(capsule), workspace: draft_workspace_payload(capsule)}}
    end
  end

  def create_draft_proposal(agent_claims, capsule_id, attrs) when is_map(attrs) do
    wallet = Helpers.required_wallet(agent_claims)
    workspace = Helpers.required_map(attrs, "workspace")
    proposal_id = "proposal_" <> Helpers.unique_suffix()

    with {:ok, capsule} <- Helpers.fetch_capsule(capsule_id),
         true <- capsule.split == @draft_split || {:error, :capsule_not_found},
         {:ok, proposal} <-
           %DraftProposal{}
           |> DraftProposal.changeset(%{
             proposal_id: proposal_id,
             capsule_id: capsule_id,
             proposer_wallet_address: wallet,
             summary: Helpers.required_binary(attrs, "summary"),
             workspace_bundle: workspace,
             patch_json: Helpers.optional_map(attrs, "patch_json") || %{},
             workspace_manifest_hash: Helpers.required_binary(attrs, "workspace_manifest_hash"),
             status: :open
           })
           |> Repo.insert() do
      {:ok, %{proposal: proposal_payload(proposal)}}
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def list_draft_proposals(capsule_id) when is_binary(capsule_id) do
    DraftProposal
    |> where([proposal], proposal.capsule_id == ^capsule_id)
    |> order_by([proposal], asc: proposal.inserted_at)
    |> Repo.all()
    |> Enum.map(&proposal_payload/1)
  end

  def apply_draft_proposal(capsule_id, proposal_id)
      when is_binary(capsule_id) and is_binary(proposal_id) do
    with {:ok, capsule} <- Helpers.fetch_capsule(capsule_id),
         %DraftProposal{} = proposal <-
           Repo.get_by(DraftProposal, proposal_id: proposal_id, capsule_id: capsule_id) ||
             {:error, :proposal_not_found},
         true <- capsule.split == @draft_split || {:error, :capsule_not_found} do
      Multi.new()
      |> Multi.update(
        :capsule,
        Capsule.changeset(capsule, capsule_workspace_attrs(proposal.workspace_bundle))
      )
      |> Multi.update(:proposal, DraftProposal.changeset(proposal, %{status: :accepted}))
      |> Repo.transaction()
      |> case do
        {:ok, %{capsule: updated}} ->
          {:ok,
           %{capsule: draft_capsule_payload(updated), workspace: draft_workspace_payload(updated)}}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def ready_draft(agent_claims, capsule_id) when is_binary(capsule_id) do
    wallet = Helpers.required_wallet(agent_claims)

    with {:ok, capsule} <- Helpers.fetch_capsule(capsule_id),
         true <- capsule.split == @draft_split || {:error, :capsule_not_found},
         true <- capsule.owner_wallet_address == wallet || {:error, :draft_not_owned} do
      request_id = "review_req_" <> Helpers.unique_suffix()

      Multi.new()
      |> Multi.update(
        :capsule,
        Capsule.changeset(capsule, %{workflow_state: :review_ready})
      )
      |> Multi.run(:review_request, fn repo, %{capsule: updated_capsule} ->
        existing =
          repo.one(
            from request in ReviewRequest,
              where:
                request.capsule_id == ^updated_capsule.capsule_id and
                  request.state in ^@review_open_states,
              limit: 1
          )

        if existing do
          {:ok, existing}
        else
          %ReviewRequest{}
          |> ReviewRequest.changeset(%{
            request_id: request_id,
            capsule_id: updated_capsule.capsule_id,
            review_kind: :certification,
            visibility: :public_claim,
            state: :open
          })
          |> repo.insert()
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{capsule: updated_capsule}} ->
          {:ok,
           %{
             capsule: draft_capsule_payload(updated_capsule),
             workspace: draft_workspace_payload(updated_capsule)
           }}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def draft_capsule_payload(%Capsule{} = capsule) do
    %{
      capsule_id: capsule.capsule_id,
      title: capsule.title,
      split: "draft",
      workflow_state: enum_value(capsule.workflow_state),
      owner_wallet_address: capsule.owner_wallet_address,
      source_node_id: capsule.source_node_id,
      seed: capsule.seed,
      parent_id: capsule.parent_id,
      inserted_at: capsule.inserted_at,
      updated_at: capsule.updated_at,
      published_at: capsule.published_at,
      hypothesis: capsule.hypothesis,
      protocol_md: capsule.protocol_md,
      rubric_json: capsule.rubric_json,
      capsule_source: capsule.capsule_source,
      recommended_genome_source: capsule.recommended_genome_source,
      genome_notes_md: capsule.genome_notes_md,
      certificate: certificate_summary_payload(capsule)
    }
  end

  def draft_workspace_payload(%Capsule{} = capsule) do
    %{
      notebook_py: capsule.notebook_py || "",
      hypothesis_md: capsule.hypothesis || "",
      protocol_md: capsule.protocol_md || "",
      rubric_json: capsule.rubric_json || %{},
      capsule_source: capsule.capsule_source || %{},
      recommended_genome_source:
        if(
          is_map(capsule.recommended_genome_source) and
            map_size(capsule.recommended_genome_source) > 0,
          do: capsule.recommended_genome_source,
          else: nil
        ),
      genome_notes_md: capsule.genome_notes_md
    }
  end

  def proposal_payload(nil), do: nil

  def proposal_payload(%DraftProposal{} = proposal) do
    %{
      proposal_id: proposal.proposal_id,
      capsule_id: proposal.capsule_id,
      proposer_wallet_address: proposal.proposer_wallet_address,
      summary: proposal.summary,
      patch_json: proposal.patch_json,
      workspace_manifest_hash: proposal.workspace_manifest_hash,
      status: enum_value(proposal.status),
      inserted_at: proposal.inserted_at,
      updated_at: proposal.updated_at
    }
  end

  defp certificate_summary_payload(%Capsule{} = capsule) do
    %{
      capsule_id: capsule.capsule_id,
      status: enum_value(capsule.certificate_status || :none),
      certificate_review_id: capsule.certificate_review_id,
      scope: capsule.certificate_scope,
      issued_at: capsule.updated_at,
      expires_at: capsule.certificate_expires_at,
      reviewer_wallet: certificate_reviewer_wallet(capsule)
    }
  end

  defp enum_value(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_value(value), do: value

  defp certificate_reviewer_wallet(%Capsule{certificate_review_id: nil}), do: nil

  defp certificate_reviewer_wallet(%Capsule{certificate_review_id: review_node_id}) do
    case Repo.get_by(ReviewSubmission, review_node_id: review_node_id) do
      nil -> nil
      submission -> submission.reviewer_wallet
    end
  end

  defp capsule_workspace_attrs(workspace) do
    %{
      title: Map.get(workspace, "title"),
      hypothesis: workspace_hypothesis(workspace),
      protocol_md: Helpers.required_binary(workspace, "protocol_md"),
      rubric_json: Helpers.required_map(workspace, "rubric_json"),
      task_json: Helpers.required_map(workspace, "capsule_source"),
      notebook_py: Helpers.required_binary(workspace, "notebook_py"),
      capsule_source: Helpers.required_map(workspace, "capsule_source"),
      recommended_genome_source:
        Helpers.optional_map(workspace, "recommended_genome_source") || %{},
      genome_notes_md: Helpers.optional_binary(workspace, "genome_notes_md")
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp workspace_hypothesis(workspace) do
    Helpers.optional_binary(workspace, "hypothesis_md") ||
      Helpers.required_binary(workspace, "protocol_md")
  end
end
