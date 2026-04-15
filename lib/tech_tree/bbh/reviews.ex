defmodule TechTree.BBH.Reviews do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi

  alias TechTree.BBH.{
    Capsule,
    DraftProposal,
    Drafts,
    Helpers,
    ReviewRequest,
    ReviewSubmission,
    Reviewers
  }

  alias TechTree.Repo
  alias TechTree.V1.{Node, Review}

  @certificate_ttl_days 365
  @review_kinds ~w(design genome certification)
  @review_open_states ~w(open claimed)
  @review_decisions ~w(approve approve_with_edits changes_requested reject)

  def list_reviews(agent_claims, attrs \\ %{}) do
    with {:ok, _profile} <- Reviewers.require_approved_reviewer(agent_claims) do
      kind = Map.get(attrs, "kind") || Map.get(attrs, :kind)

      requests =
        ReviewRequest
        |> maybe_filter_review_kind(kind)
        |> where([request], request.state in ^@review_open_states)
        |> order_by([request], asc: request.inserted_at)
        |> Repo.all()

      capsules_by_id = review_capsules_by_id(requests)

      requests
      |> Enum.map(&review_request_payload(&1, capsules_by_id))
      |> then(&{:ok, &1})
    end
  end

  def claim_review(agent_claims, request_id) when is_binary(request_id) do
    with {:ok, profile} <- Reviewers.require_approved_reviewer(agent_claims),
         %ReviewRequest{} = request <-
           Repo.get(ReviewRequest, request_id) || {:error, :review_request_not_found},
         true <- request.state == "open" || {:error, :review_request_not_claimable},
         %Capsule{} = capsule <-
           Repo.get(Capsule, request.capsule_id) || {:error, :capsule_not_found} do
      Multi.new()
      |> Multi.update(
        :request,
        ReviewRequest.changeset(request, %{
          state: "claimed",
          claimed_by_wallet: profile.wallet_address
        })
      )
      |> Multi.update(:capsule, Capsule.changeset(capsule, %{workflow_state: "in_review"}))
      |> Repo.transaction()
      |> case do
        {:ok, %{request: updated}} -> {:ok, review_request_payload(updated)}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  def get_review_packet(agent_claims, request_id) when is_binary(request_id) do
    wallet = Helpers.required_wallet(agent_claims)

    with {:ok, _profile} <- Reviewers.require_approved_reviewer(agent_claims),
         %ReviewRequest{} = request <-
           Repo.get(ReviewRequest, request_id) || {:error, :review_request_not_found},
         true <-
           (request.state == "open" or request.claimed_by_wallet == wallet) ||
             {:error, :review_request_not_claimed},
         %Capsule{} = capsule <-
           Repo.get(Capsule, request.capsule_id) || {:error, :capsule_not_found} do
      proposals =
        DraftProposal
        |> where([proposal], proposal.capsule_id == ^capsule.capsule_id)
        |> order_by([proposal], asc: proposal.inserted_at)
        |> Repo.all()
        |> Enum.map(&Drafts.proposal_payload/1)

      {:ok,
       %{
         request: review_request_payload(request),
         capsule: Drafts.draft_capsule_payload(capsule),
         workspace: Drafts.draft_workspace_payload(capsule),
         prior_proposals: proposals,
         evidence_pack_summary: %{
           proposal_count: length(proposals),
           current_workflow_state: capsule.workflow_state
         },
         checklist_template: %{
           completeness: false,
           reproducibility: false,
           safety: false,
           notes: [],
           decision: "changes_requested"
         },
         certificate_payload: capsule_certificate_payload(capsule)
       }}
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def submit_review(agent_claims, request_id, attrs)
      when is_binary(request_id) and is_map(attrs) do
    wallet = Helpers.required_wallet(agent_claims)

    with {:ok, profile} <- Reviewers.require_approved_reviewer(agent_claims),
         true <- body_request_id_matches?(request_id, attrs) || {:error, :review_request_mismatch},
         %ReviewRequest{} = request <-
           Repo.get(ReviewRequest, request_id) || {:error, :review_request_not_found},
         true <- request.claimed_by_wallet == wallet || {:error, :review_request_not_claimed},
         %Capsule{} = capsule <-
           Repo.get(Capsule, request.capsule_id) || {:error, :capsule_not_found},
         decision <- Helpers.required_binary(attrs, "decision"),
         true <-
           decision in @review_decisions ||
             {:error, ArgumentError.exception("decision is invalid")} do
      submission_id = "review_sub_" <> Helpers.unique_suffix()

      review_node_id =
        if(decision in ["approve", "approve_with_edits"],
          do: "0xreview" <> Helpers.random_hex(58),
          else: nil
        )

      certificate_payload = Helpers.optional_map(attrs, "certificate_payload") || %{}
      genome_source = Helpers.optional_map(attrs, "genome_recommendation_source") || %{}

      Multi.new()
      |> Multi.insert(
        :submission,
        ReviewSubmission.changeset(%ReviewSubmission{}, %{
          submission_id: submission_id,
          request_id: request.request_id,
          capsule_id: capsule.capsule_id,
          reviewer_wallet: profile.wallet_address,
          checklist_json: Helpers.required_map(attrs, "checklist_json"),
          suggested_edits_json: Helpers.required_map(attrs, "suggested_edits_json"),
          decision: decision,
          summary_md: Helpers.required_binary(attrs, "summary_md"),
          genome_recommendation_source: genome_source,
          certificate_payload: certificate_payload,
          review_node_id: review_node_id
        })
      )
      |> Multi.run(:review_node, fn repo, _changes ->
        maybe_insert_certificate_review_node(repo, capsule, profile, decision, review_node_id)
      end)
      |> Multi.update(
        :request,
        ReviewRequest.changeset(request, %{state: "closed", closed_at: DateTime.utc_now()})
      )
      |> Multi.update(
        :capsule,
        Capsule.changeset(capsule, capsule_review_outcome_attrs(decision, review_node_id))
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{submission: submission}} ->
          {:ok, %{submission: review_submission_payload(submission)}}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  defp review_request_payload(%ReviewRequest{} = request) do
    capsule = Repo.get(Capsule, request.capsule_id)
    review_request_payload(request, %{request.capsule_id => capsule})
  end

  defp review_request_payload(%ReviewRequest{} = request, capsules_by_id)
       when is_map(capsules_by_id) do
    capsule = Map.get(capsules_by_id, request.capsule_id)

    %{
      request_id: request.request_id,
      capsule_id: request.capsule_id,
      review_kind: request.review_kind,
      visibility: request.visibility,
      state: request.state,
      capsule_title: capsule && capsule.title,
      claimed_by_wallet: request.claimed_by_wallet,
      fee_quote_usdc: request.fee_quote_usdc,
      holdback_usdc: request.holdback_usdc,
      due_at: request.due_at,
      inserted_at: request.inserted_at,
      updated_at: request.updated_at
    }
  end

  defp review_capsules_by_id(requests) do
    capsule_ids =
      requests
      |> Enum.map(& &1.capsule_id)
      |> Enum.uniq()

    Capsule
    |> where([capsule], capsule.capsule_id in ^capsule_ids)
    |> Repo.all()
    |> Map.new(&{&1.capsule_id, &1})
  end

  defp review_submission_payload(%ReviewSubmission{} = submission) do
    %{
      submission_id: submission.submission_id,
      request_id: submission.request_id,
      capsule_id: submission.capsule_id,
      reviewer_wallet: submission.reviewer_wallet,
      checklist_json: submission.checklist_json,
      suggested_edits_json: submission.suggested_edits_json,
      decision: submission.decision,
      summary_md: submission.summary_md,
      genome_recommendation_source:
        if(
          is_map(submission.genome_recommendation_source) and
            map_size(submission.genome_recommendation_source) > 0,
          do: submission.genome_recommendation_source,
          else: nil
        ),
      review_node_id: submission.review_node_id,
      inserted_at: submission.inserted_at,
      updated_at: submission.updated_at
    }
  end

  defp capsule_certificate_payload(%Capsule{} = capsule) do
    %{
      kind: "capsule_certificate",
      capsule_id: capsule.capsule_id,
      artifact_id: capsule.publication_artifact_id,
      review_id: capsule.certificate_review_id,
      status: capsule.certificate_status || "none",
      title: capsule.title
    }
  end

  defp body_request_id_matches?(request_id, attrs) do
    case Helpers.optional_binary(attrs, "request_id") do
      nil -> true
      ^request_id -> true
      _ -> false
    end
  end

  defp capsule_review_outcome_attrs(decision, review_node_id) do
    case decision do
      "approve" ->
        %{
          workflow_state: "approved",
          certificate_status: "active",
          certificate_review_id: review_node_id,
          certificate_scope: "publication",
          certificate_expires_at:
            DateTime.add(DateTime.utc_now(), @certificate_ttl_days * 86_400, :second)
        }

      "approve_with_edits" ->
        %{
          workflow_state: "approved",
          certificate_status: "active",
          certificate_review_id: review_node_id,
          certificate_scope: "publication",
          certificate_expires_at:
            DateTime.add(DateTime.utc_now(), @certificate_ttl_days * 86_400, :second)
        }

      "changes_requested" ->
        %{workflow_state: "authoring", certificate_status: "none", certificate_review_id: nil}

      "reject" ->
        %{workflow_state: "rejected", certificate_status: "none", certificate_review_id: nil}
    end
  end

  defp maybe_insert_certificate_review_node(_repo, _capsule, _profile, decision, nil)
       when decision in ["changes_requested", "reject"],
       do: {:ok, nil}

  defp maybe_insert_certificate_review_node(repo, capsule, profile, decision, review_node_id)
       when decision in ["approve", "approve_with_edits"] do
    now = DateTime.utc_now()
    target_id = capsule.publication_artifact_id || capsule.capsule_id

    with {:ok, _node} <-
           %Node{}
           |> Node.changeset(%{
             id: review_node_id,
             node_type: 3,
             author: profile.wallet_address,
             subject_id: review_node_id,
             aux_id: target_id,
             payload_hash: "sha256:" <> String.duplicate("1", 64),
             schema_version: 1,
             verification_status: "verified",
             tx_hash: "0x" <> Helpers.random_hex(64),
             block_number: 1,
             block_time: now,
             header: %{"id" => review_node_id},
             manifest: %{
               "target" => %{
                 "type" => if(capsule.publication_artifact_id, do: "artifact", else: "capsule"),
                 "id" => target_id
               },
               "kind" => "capsule_certificate",
               "method" => "manual",
               "result" => "confirmed",
               "summary" => "Approved BBH capsule certificate"
             },
             payload_index: %{}
           })
           |> repo.insert(),
         {:ok, _review} <-
           %Review{}
           |> Review.changeset(%{
             id: review_node_id,
             target_type: if(capsule.publication_artifact_id, do: "artifact", else: "capsule"),
             target_id: target_id,
             kind: "capsule_certificate",
             method: "manual",
             result: "confirmed",
             scope_level: "whole",
             scope_path: nil
           })
           |> repo.insert() do
      {:ok, review_node_id}
    end
  end

  defp maybe_filter_review_kind(query, nil), do: query

  defp maybe_filter_review_kind(query, kind) when kind in @review_kinds do
    where(query, [request], request.review_kind == ^kind)
  end

  defp maybe_filter_review_kind(query, _kind), do: query
end
