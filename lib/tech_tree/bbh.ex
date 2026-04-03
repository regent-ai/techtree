defmodule TechTree.BBH do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias TechTree.Repo

  alias TechTree.BBH.{
    Assignment,
    Capsule,
    DraftProposal,
    Genome,
    OrcidLinkRequest,
    ReviewRequest,
    ReviewSubmission,
    ReviewerProfile,
    Run,
    Validation
  }

  alias TechTree.V1.{Artifact, Node, Review}

  @climb_split "climb"
  @benchmark_split "benchmark"
  @challenge_split "challenge"
  @draft_split "draft"
  @public_splits [@climb_split, @benchmark_split, @challenge_split]
  @official_splits [@benchmark_split, @challenge_split]
  @auto_assignment_policies ["auto", "auto_or_select"]
  @select_assignment_policies ["select", "auto_or_select"]
  @review_kinds ~w(design genome certification)
  @review_open_states ~w(open claimed)
  @review_decisions ~w(approve approve_with_edits changes_requested reject)
  @orcid_link_ttl_seconds 600
  @certificate_ttl_days 365

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
    capsule_id = required_binary(attrs, "capsule_id")

    with :ok <- ensure_inventory_loaded(),
         {:ok, capsule} <- fetch_capsule(capsule_id),
         :ok <- ensure_public_capsule_visible?(capsule),
         :ok <- ensure_capsule_selectable(capsule) do
      build_assignment_payload(agent_claims, capsule)
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def create_run(attrs) when is_map(attrs) do
    genome_source = required_map(attrs, "genome_source")
    run_source = required_map(attrs, "run_source")
    workspace = required_map(attrs, "workspace")
    artifact_source = optional_map(attrs, "artifact_source")
    run_id = required_binary(attrs, "run_id")
    capsule_id = required_binary(attrs, "capsule_id")
    assignment_ref = optional_binary(attrs, "assignment_ref")

    with {:ok, capsule} <- fetch_capsule(capsule_id),
         :ok <- validate_assignment_requirement(capsule.split, assignment_ref),
         {:ok, genome_id, genome_changeset} <- genome_changeset(genome_source),
         {:ok, score} <- score_from_workspace(workspace),
         {:ok, run_changeset} <-
           run_changeset(
             run_id,
             capsule,
             genome_id,
             assignment_ref,
             run_source,
             genome_source,
             artifact_source,
             workspace,
             score
           ) do
      Multi.new()
      |> Multi.insert(:genome, genome_changeset,
        on_conflict: {:replace_all_except, [:genome_id, :inserted_at]},
        conflict_target: :genome_id
      )
      |> Multi.insert(:run, run_changeset)
      |> Multi.run(:assignment, fn repo, %{run: run} ->
        maybe_complete_assignment(repo, run.assignment_ref)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{run: run}} ->
          {:ok, %{run: run, genome: Repo.get!(Genome, genome_id)}}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  def create_validation(attrs) when is_map(attrs) do
    review_source = required_map(attrs, "review_source")
    validation_id = required_binary(attrs, "validation_id")
    run_id = required_binary(attrs, "run_id")
    workspace = optional_map(attrs, "workspace") || %{}

    with %Run{} = run <- Repo.get(Run, run_id),
         {:ok, validation_changeset} <-
           validation_changeset(validation_id, run, review_source, workspace) do
      Multi.new()
      |> Multi.insert(:validation, validation_changeset)
      |> Multi.update(:run, Ecto.Changeset.change(run, status: next_run_status(review_source)))
      |> Repo.transaction()
      |> case do
        {:ok, %{validation: validation}} -> {:ok, validation}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      nil -> {:error, :run_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_status(run_ids) when is_list(run_ids) do
    runs =
      Run
      |> where([run], run.run_id in ^run_ids)
      |> Repo.all()

    statuses =
      Enum.map(runs, fn run ->
        latest_validation =
          Validation
          |> where([validation], validation.run_id == ^run.run_id)
          |> order_by([validation], desc: validation.inserted_at)
          |> limit(1)
          |> Repo.one()

        %{
          run_id: run.run_id,
          status: run.status,
          raw_score: run.raw_score,
          normalized_score: run.normalized_score,
          validation_status: latest_validation && latest_validation.result
        }
      end)

    %{runs: statuses}
  end

  def leaderboard(opts \\ %{}) do
    split = Map.get(opts, "split") || Map.get(opts, :split) || @benchmark_split

    runs_query =
      from run in Run,
        join: validation in Validation,
        on: validation.run_id == run.run_id,
        join: genome in Genome,
        on: genome.genome_id == run.genome_id,
        join: capsule in Capsule,
        on: capsule.capsule_id == run.capsule_id,
        where:
          run.split == ^split and
            run.status == "validated" and
            validation.role == "official" and
            validation.method == "replay" and
            validation.result == "confirmed",
        order_by: [desc: run.normalized_score, desc: run.updated_at]

    entries =
      runs_query
      |> Repo.all()
      |> Enum.group_by(& &1.genome_id)
      |> Enum.map(fn {_genome_id, runs} ->
        run = Enum.max_by(runs, &(&1.normalized_score || -1.0))
        genome = Repo.get!(Genome, run.genome_id)

        %{
          rank: 0,
          run_id: run.run_id,
          genome_id: genome.genome_id,
          name: genome.label || genome.genome_id,
          score_percent: Float.round((run.normalized_score || 0.0) * 100.0, 1),
          final_objective_hit_rate: if((run.raw_score || 0.0) > 0, do: 1.0, else: 0.0),
          validated_runs: length(runs),
          reproducibility_rate: 1.0,
          median_latency_sec: nil,
          median_cost_usd: nil,
          harness_type: genome.harness_type,
          model_id: genome.model_id,
          updated_at: run.updated_at
        }
      end)
      |> Enum.sort_by(fn entry -> {-entry.score_percent, -entry.validated_runs, entry.name} end)
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, index} -> %{entry | rank: index} end)

    %{
      benchmark: "bbh_py",
      split: split,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      entries: entries
    }
  end

  defdelegate list_runs(opts \\ %{}), to: TechTree.BBH.PublicReads
  defdelegate list_capsules(opts \\ %{}), to: TechTree.BBH.PublicReads
  defdelegate list_public_capsules(opts \\ %{}), to: TechTree.BBH.PublicReads
  defdelegate get_public_capsule(capsule_id), to: TechTree.BBH.PublicReads
  defdelegate get_run(run_id), to: TechTree.BBH.PublicReads
  defdelegate get_genome(genome_id), to: TechTree.BBH.PublicReads
  defdelegate list_validations(run_id), to: TechTree.BBH.PublicReads

  def create_draft(agent_claims, attrs) when is_map(attrs) do
    wallet = required_wallet(agent_claims)
    title = required_binary(attrs, "title")
    workspace = required_map(attrs, "workspace")
    capsule_id = draft_capsule_id()

    %Capsule{}
    |> Capsule.changeset(%{
      capsule_id: capsule_id,
      provider: "techtree",
      provider_ref: "draft/#{capsule_id}",
      family_ref: optional_binary(attrs, "seed"),
      instance_ref: capsule_id,
      split: @draft_split,
      language: "python",
      mode: "fixed",
      assignment_policy: "operator",
      title: title,
      hypothesis: workspace_hypothesis(workspace),
      protocol_md: required_binary(workspace, "protocol_md"),
      rubric_json: required_map(workspace, "rubric_json"),
      task_json: required_map(workspace, "capsule_source"),
      data_files: [],
      artifact_source: %{},
      owner_wallet_address: wallet,
      source_node_id: fetch_value(attrs, "source_node_id"),
      seed: optional_binary(attrs, "seed"),
      parent_id: fetch_value(attrs, "parent_id"),
      workflow_state: "authoring",
      notebook_py: required_binary(workspace, "notebook_py"),
      capsule_source: required_map(workspace, "capsule_source"),
      recommended_genome_source: optional_map(workspace, "recommended_genome_source") || %{},
      genome_notes_md: optional_binary(workspace, "genome_notes_md"),
      certificate_status: "none"
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
    wallet = required_wallet(agent_claims)

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
    with {:ok, capsule} <- fetch_capsule(capsule_id),
         true <- capsule.split == @draft_split || {:error, :capsule_not_found} do
      {:ok,
       %{capsule: draft_capsule_payload(capsule), workspace: draft_workspace_payload(capsule)}}
    end
  end

  def create_draft_proposal(agent_claims, capsule_id, attrs) when is_map(attrs) do
    wallet = required_wallet(agent_claims)
    workspace = required_map(attrs, "workspace")
    proposal_id = "proposal_" <> unique_suffix()

    with {:ok, capsule} <- fetch_capsule(capsule_id),
         true <- capsule.split == @draft_split || {:error, :capsule_not_found},
         {:ok, proposal} <-
           %DraftProposal{}
           |> DraftProposal.changeset(%{
             proposal_id: proposal_id,
             capsule_id: capsule_id,
             proposer_wallet_address: wallet,
             summary: required_binary(attrs, "summary"),
             workspace_bundle: workspace,
             patch_json: optional_map(attrs, "patch_json") || %{},
             workspace_manifest_hash: required_binary(attrs, "workspace_manifest_hash"),
             status: "open"
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
    with {:ok, capsule} <- fetch_capsule(capsule_id),
         %DraftProposal{} = proposal <-
           Repo.get_by(DraftProposal, proposal_id: proposal_id, capsule_id: capsule_id) ||
             {:error, :proposal_not_found},
         true <- capsule.split == @draft_split || {:error, :capsule_not_found} do
      Multi.new()
      |> Multi.update(
        :capsule,
        Capsule.changeset(capsule, capsule_workspace_attrs(proposal.workspace_bundle))
      )
      |> Multi.update(:proposal, DraftProposal.changeset(proposal, %{status: "accepted"}))
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
    wallet = required_wallet(agent_claims)

    with {:ok, capsule} <- fetch_capsule(capsule_id),
         true <- capsule.split == @draft_split || {:error, :capsule_not_found},
         true <- capsule.owner_wallet_address == wallet || {:error, :draft_not_owned} do
      request_id = "review_req_" <> unique_suffix()

      Multi.new()
      |> Multi.update(
        :capsule,
        Capsule.changeset(capsule, %{workflow_state: "review_ready"})
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
            review_kind: "certification",
            visibility: "public_claim",
            state: "open"
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

  def start_reviewer_orcid_link(agent_claims) do
    wallet = required_wallet(agent_claims)
    request_id = "orcid_req_" <> unique_suffix()
    expires_at = DateTime.add(DateTime.utc_now(), @orcid_link_ttl_seconds, :second)

    %OrcidLinkRequest{}
    |> OrcidLinkRequest.changeset(%{
      request_id: request_id,
      wallet_address: wallet,
      state: "pending",
      expires_at: expires_at
    })
    |> Repo.insert()
    |> case do
      {:ok, request} ->
        {:ok,
         %{
           request_id: request.request_id,
           state: request.state,
           start_url:
             "#{TechTreeWeb.Endpoint.url()}/auth/orcid/start?request_id=#{request.request_id}",
           reviewer: reviewer_profile_payload(Repo.get(ReviewerProfile, wallet))
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_reviewer_orcid_link_status(agent_claims, request_id) when is_binary(request_id) do
    wallet = required_wallet(agent_claims)

    case Repo.get(OrcidLinkRequest, request_id) do
      nil ->
        {:error, :orcid_request_not_found}

      %OrcidLinkRequest{} = request ->
        request = maybe_expire_orcid_request(request)

        if request.wallet_address != wallet do
          {:error, :orcid_request_not_found}
        else
          {:ok,
           %{
             request_id: request.request_id,
             state: request.state,
             start_url:
               if(request.state == "pending",
                 do:
                   "#{TechTreeWeb.Endpoint.url()}/auth/orcid/start?request_id=#{request.request_id}",
                 else: nil
               ),
             reviewer: reviewer_profile_payload(Repo.get(ReviewerProfile, wallet))
           }}
        end
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def apply_reviewer(agent_claims, attrs) when is_map(attrs) do
    wallet = required_wallet(agent_claims)
    domain_tags = fetch_value(attrs, "domain_tags")

    with true <-
           is_list(domain_tags) || {:error, ArgumentError.exception("domain_tags is required")},
         %ReviewerProfile{} = profile <-
           Repo.get(ReviewerProfile, wallet) || {:error, :reviewer_orcid_required},
         true <-
           (profile.orcid_auth_kind == "oauth_authenticated" and is_binary(profile.orcid_id)) ||
             {:error, :reviewer_orcid_required},
         {:ok, updated} <-
           profile
           |> ReviewerProfile.changeset(%{
             domain_tags: Enum.map(domain_tags, &to_string/1),
             payout_wallet: optional_binary(attrs, "payout_wallet"),
             experience_summary: optional_binary(attrs, "experience_summary")
           })
           |> Repo.update() do
      {:ok, reviewer_profile_payload(updated)}
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def get_reviewer(agent_claims) do
    wallet = required_wallet(agent_claims)

    {:ok,
     reviewer_profile_payload(
       Repo.get(ReviewerProfile, wallet) ||
         %ReviewerProfile{wallet_address: wallet, vetting_status: "pending", domain_tags: []}
     )}
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def approve_reviewer(wallet_address, admin_ref, status)
      when status in ["approved", "rejected"] do
    profile =
      Repo.get(ReviewerProfile, wallet_address) ||
        %ReviewerProfile{wallet_address: wallet_address, domain_tags: []}

    profile
    |> ReviewerProfile.changeset(%{
      vetting_status: status,
      vetted_by: admin_ref,
      vetted_at: DateTime.utc_now()
    })
    |> Repo.insert_or_update()
    |> case do
      {:ok, updated} -> {:ok, reviewer_profile_payload(updated)}
      {:error, reason} -> {:error, reason}
    end
  end

  def list_reviews(agent_claims, attrs \\ %{}) do
    with {:ok, _profile} <- require_approved_reviewer(agent_claims) do
      kind = Map.get(attrs, "kind") || Map.get(attrs, :kind)

      ReviewRequest
      |> maybe_filter_review_kind(kind)
      |> where([request], request.state in ^@review_open_states)
      |> order_by([request], asc: request.inserted_at)
      |> Repo.all()
      |> Enum.map(&review_request_payload/1)
      |> then(&{:ok, &1})
    end
  end

  def claim_review(agent_claims, request_id) when is_binary(request_id) do
    with {:ok, profile} <- require_approved_reviewer(agent_claims),
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
    wallet = required_wallet(agent_claims)

    with {:ok, _profile} <- require_approved_reviewer(agent_claims),
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
        |> Enum.map(&proposal_payload/1)

      {:ok,
       %{
         request: review_request_payload(request),
         capsule: draft_capsule_payload(capsule),
         workspace: draft_workspace_payload(capsule),
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
    wallet = required_wallet(agent_claims)

    with {:ok, profile} <- require_approved_reviewer(agent_claims),
         true <- body_request_id_matches?(request_id, attrs) || {:error, :review_request_mismatch},
         %ReviewRequest{} = request <-
           Repo.get(ReviewRequest, request_id) || {:error, :review_request_not_found},
         true <- request.claimed_by_wallet == wallet || {:error, :review_request_not_claimed},
         %Capsule{} = capsule <-
           Repo.get(Capsule, request.capsule_id) || {:error, :capsule_not_found},
         decision <- required_binary(attrs, "decision"),
         true <-
           decision in @review_decisions ||
             {:error, ArgumentError.exception("decision is invalid")} do
      submission_id = "review_sub_" <> unique_suffix()

      review_node_id =
        if(decision in ["approve", "approve_with_edits"],
          do: "0xreview" <> random_hex(58),
          else: nil
        )

      certificate_payload = optional_map(attrs, "certificate_payload") || %{}
      genome_source = optional_map(attrs, "genome_recommendation_source") || %{}

      Multi.new()
      |> Multi.insert(
        :submission,
        ReviewSubmission.changeset(%ReviewSubmission{}, %{
          submission_id: submission_id,
          request_id: request.request_id,
          capsule_id: capsule.capsule_id,
          reviewer_wallet: profile.wallet_address,
          checklist_json: required_map(attrs, "checklist_json"),
          suggested_edits_json: required_map(attrs, "suggested_edits_json"),
          decision: decision,
          summary_md: required_binary(attrs, "summary_md"),
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

  defdelegate certificate_summary(capsule_id), to: TechTree.BBH.PublicReads
  defdelegate review_open_count(capsule_id), to: TechTree.BBH.PublicReads

  def complete_orcid_link(request_id) when is_binary(request_id) do
    case Repo.get(OrcidLinkRequest, request_id) do
      nil ->
        {:error, :orcid_request_not_found}

      %OrcidLinkRequest{} = request ->
        request = maybe_expire_orcid_request(request)

        if request.state != "pending" do
          {:error, :orcid_request_expired}
        else
          orcid_id = generated_orcid_id(request.wallet_address)
          orcid_name = "Reviewer #{String.slice(request.wallet_address, -4, 4)}"

          Multi.new()
          |> Multi.update(
            :request,
            OrcidLinkRequest.changeset(request, %{
              state: "authenticated",
              authenticated_at: DateTime.utc_now()
            })
          )
          |> Multi.run(:reviewer, fn repo, _changes ->
            profile =
              repo.get(ReviewerProfile, request.wallet_address) ||
                %ReviewerProfile{wallet_address: request.wallet_address, domain_tags: []}

            profile
            |> ReviewerProfile.changeset(%{
              orcid_id: orcid_id,
              orcid_auth_kind: "oauth_authenticated",
              orcid_name: orcid_name,
              vetting_status: profile.vetting_status || "pending"
            })
            |> repo.insert_or_update()
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{reviewer: reviewer}} -> {:ok, reviewer_profile_payload(reviewer)}
            {:error, _step, reason, _changes} -> {:error, reason}
          end
        end
    end
  end

  def upsert_capsule(attrs) when is_map(attrs) do
    capsule_id = required_binary(attrs, "capsule_id")

    %Capsule{}
    |> Capsule.changeset(%{
      capsule_id: capsule_id,
      provider: required_binary(attrs, "provider"),
      provider_ref: required_binary(attrs, "provider_ref"),
      family_ref: optional_binary(attrs, "family_ref"),
      instance_ref: optional_binary(attrs, "instance_ref"),
      split: required_binary(attrs, "split"),
      language: Map.get(attrs, "language", "python"),
      mode: Map.get(attrs, "mode", infer_mode(attrs)),
      assignment_policy: required_binary(attrs, "assignment_policy"),
      title: required_binary(attrs, "title"),
      hypothesis: required_binary(attrs, "hypothesis"),
      protocol_md: required_binary(attrs, "protocol_md"),
      rubric_json: required_map(attrs, "rubric_json"),
      task_json: required_map(attrs, "task_json"),
      data_files: Map.get(attrs, "data_files", []),
      artifact_source: optional_map(attrs, "artifact_source") || %{},
      publication_artifact_id: optional_binary(attrs, "publication_artifact_id"),
      publication_review_id: optional_binary(attrs, "publication_review_id"),
      published_at: fetch_value(attrs, "published_at")
    })
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:capsule_id, :inserted_at]},
      conflict_target: :capsule_id
    )
  end

  defp fetch_capsule(capsule_id) do
    case Repo.get(Capsule, capsule_id) do
      nil -> {:error, :capsule_not_found}
      capsule -> {:ok, capsule}
    end
  end

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

  defp ensure_inventory_loaded do
    if Repo.aggregate(Capsule, :count, :capsule_id) > 0 do
      :ok
    else
      {:error, :capsule_inventory_empty}
    end
  end

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

  defp validate_assignment_requirement(split, assignment_ref)
       when split in @official_splits and (is_nil(assignment_ref) or assignment_ref == ""),
       do: {:error, :assignment_ref_required}

  defp validate_assignment_requirement(_split, _assignment_ref), do: :ok

  defp genome_changeset(source) do
    genome_id = source["genome_id"] || fingerprint_genome(source)

    attrs = %{
      genome_id: genome_id,
      label: source["label"],
      parent_genome_ref: source["parent_genome_ref"],
      model_id: required_binary(source, "model_id"),
      harness_type: required_binary(source, "harness_type"),
      harness_version: required_binary(source, "harness_version"),
      prompt_pack_version: required_binary(source, "prompt_pack_version"),
      skill_pack_version: required_binary(source, "skill_pack_version"),
      tool_profile: required_binary(source, "tool_profile"),
      runtime_image: required_binary(source, "runtime_image"),
      helper_code_hash: source["helper_code_hash"],
      data_profile: source["data_profile"],
      axes: Map.get(source, "axes", %{}),
      notes: source["notes"],
      normalized_bundle_hash:
        :crypto.hash(:sha256, Jason.encode!(normalized_genome_bundle(source)))
        |> Base.encode16(case: :lower),
      source: source
    }

    {:ok, genome_id, Genome.changeset(%Genome{}, attrs)}
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  defp normalized_genome_bundle(source) do
    source
    |> Map.drop(["schema_version", "label", "parent_genome_ref", "notes", "genome_id"])
    |> Enum.sort()
    |> Map.new()
  end

  defp fingerprint_genome(source) do
    "gen_" <>
      (:crypto.hash(:sha256, Jason.encode!(normalized_genome_bundle(source)))
       |> Base.encode16(case: :lower)
       |> binary_part(0, 16))
  end

  defp run_changeset(
         run_id,
         capsule,
         genome_id,
         assignment_ref,
         run_source,
         genome_source,
         artifact_source,
         workspace,
         score
       ) do
    executor = required_map(run_source, "executor")
    status = Map.get(run_source, "status") || "completed"

    attrs = %{
      run_id: run_id,
      capsule_id: capsule.capsule_id,
      assignment_ref: assignment_ref,
      genome_id: genome_id,
      canonical_run_id: Map.get(run_source, "canonical_run_id"),
      executor_type: required_binary(executor, "type"),
      harness_type: required_binary(executor, "harness"),
      harness_version: required_binary(executor, "harness_version"),
      split: required_binary(required_map(run_source, "bbh"), "split"),
      status: normalize_run_status(status, score),
      raw_score: score.raw,
      normalized_score: score.normalized,
      analysis_py: required_binary(workspace, "analysis_py"),
      protocol_md: required_binary(workspace, "protocol_md"),
      rubric_json: required_map(workspace, "rubric_json"),
      task_json: required_map(workspace, "task_json"),
      verdict_json: required_map(workspace, "verdict_json"),
      final_answer_md: optional_binary(workspace, "final_answer_md"),
      report_html: optional_binary(workspace, "report_html"),
      run_log: optional_binary(workspace, "run_log"),
      artifact_source: artifact_source,
      genome_source: genome_source,
      run_source: run_source
    }

    {:ok, Run.changeset(%Run{}, attrs)}
  end

  defp validation_changeset(validation_id, run, review_source, workspace) do
    bbh = required_map(review_source, "bbh")

    attrs = %{
      validation_id: validation_id,
      run_id: run.run_id,
      canonical_review_id: Map.get(review_source, "canonical_review_id"),
      role: required_binary(bbh, "role"),
      method: required_binary(review_source, "method"),
      result: required_binary(review_source, "result"),
      reproduced_raw_score: bbh["reproduced_raw_score"],
      reproduced_normalized_score: bbh["reproduced_normalized_score"],
      tolerance_raw_abs: Map.get(bbh, "raw_abs_tolerance", 0.01),
      summary: required_binary(review_source, "summary"),
      review_source: review_source,
      verdict_json: optional_map(workspace, "verdict_json"),
      report_html: optional_binary(workspace, "report_html"),
      run_log: optional_binary(workspace, "run_log")
    }

    {:ok, Validation.changeset(%Validation{}, attrs)}
  end

  defp maybe_complete_assignment(_repo, nil), do: {:ok, nil}

  defp maybe_complete_assignment(repo, assignment_ref) do
    case repo.get(Assignment, assignment_ref) do
      nil ->
        {:ok, nil}

      assignment ->
        assignment
        |> Ecto.Changeset.change(status: "completed", completed_at: DateTime.utc_now())
        |> repo.update()
    end
  end

  defp next_run_status(review_source) do
    result = required_binary(review_source, "result")
    if result == "confirmed", do: "validated", else: "rejected"
  end

  defp score_from_workspace(workspace) do
    verdict = required_map(workspace, "verdict_json")
    metrics = required_map(verdict, "metrics")

    raw =
      cond do
        is_number(metrics["raw_score"]) -> metrics["raw_score"] * 1.0
        is_number(metrics["primary"]) -> metrics["primary"] * 1.0
        true -> raise ArgumentError, "workspace.verdict_json.metrics.raw_score is required"
      end

    normalized =
      cond do
        is_number(metrics["normalized_score"]) -> metrics["normalized_score"] * 1.0
        true -> raise ArgumentError, "workspace.verdict_json.metrics.normalized_score is required"
      end

    {:ok, %{raw: raw, normalized: normalized}}
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  defp normalize_run_status("completed", _score), do: "validation_pending"
  defp normalize_run_status("failed", _score), do: "failed"
  defp normalize_run_status("running", _score), do: "running"
  defp normalize_run_status(_status, _score), do: "validation_pending"

  defp infer_mode(attrs) do
    if Map.get(attrs, "family_ref") || Map.get(attrs, :family_ref), do: "family", else: "fixed"
  end

  def promote_challenge_capsule(capsule_id, attrs) when is_binary(capsule_id) and is_map(attrs) do
    artifact_id = required_binary(attrs, "publication_artifact_id")
    review_id = required_binary(attrs, "publication_review_id")

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

  defp maybe_limit_to_published_challenges(query, @challenge_split) do
    where(query, [capsule], not is_nil(capsule.published_at))
  end

  defp maybe_limit_to_published_challenges(query, _split), do: query

  defp draft_capsule_payload(%Capsule{} = capsule) do
    %{
      capsule_id: capsule.capsule_id,
      title: capsule.title,
      split: "draft",
      workflow_state: capsule.workflow_state,
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

  defp draft_workspace_payload(%Capsule{} = capsule) do
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

  defp proposal_payload(nil), do: nil

  defp proposal_payload(%DraftProposal{} = proposal) do
    %{
      proposal_id: proposal.proposal_id,
      capsule_id: proposal.capsule_id,
      proposer_wallet_address: proposal.proposer_wallet_address,
      summary: proposal.summary,
      patch_json: proposal.patch_json,
      workspace_manifest_hash: proposal.workspace_manifest_hash,
      status: proposal.status,
      inserted_at: proposal.inserted_at,
      updated_at: proposal.updated_at
    }
  end

  defp reviewer_profile_payload(nil), do: nil

  defp reviewer_profile_payload(%ReviewerProfile{} = profile) do
    %{
      wallet_address: profile.wallet_address,
      orcid_id: profile.orcid_id,
      orcid_auth_kind: profile.orcid_auth_kind,
      orcid_name: profile.orcid_name,
      vetting_status: profile.vetting_status,
      domain_tags: profile.domain_tags || [],
      payout_wallet: profile.payout_wallet,
      experience_summary: profile.experience_summary,
      vetted_by: profile.vetted_by,
      vetted_at: profile.vetted_at
    }
  end

  defp review_request_payload(%ReviewRequest{} = request) do
    capsule = Repo.get(Capsule, request.capsule_id)

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

  defp certificate_summary_payload(%Capsule{} = capsule) do
    %{
      capsule_id: capsule.capsule_id,
      status: capsule.certificate_status || "none",
      certificate_review_id: capsule.certificate_review_id,
      scope: capsule.certificate_scope,
      issued_at: capsule.updated_at,
      expires_at: capsule.certificate_expires_at,
      reviewer_wallet: certificate_reviewer_wallet(capsule)
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
      protocol_md: required_binary(workspace, "protocol_md"),
      rubric_json: required_map(workspace, "rubric_json"),
      task_json: required_map(workspace, "capsule_source"),
      notebook_py: required_binary(workspace, "notebook_py"),
      capsule_source: required_map(workspace, "capsule_source"),
      recommended_genome_source: optional_map(workspace, "recommended_genome_source") || %{},
      genome_notes_md: optional_binary(workspace, "genome_notes_md")
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp workspace_hypothesis(workspace) do
    optional_binary(workspace, "hypothesis_md") || required_binary(workspace, "protocol_md")
  end

  defp require_approved_reviewer(agent_claims) do
    wallet = required_wallet(agent_claims)

    case Repo.get(ReviewerProfile, wallet) do
      %ReviewerProfile{vetting_status: "approved"} = profile -> {:ok, profile}
      %ReviewerProfile{} -> {:error, :reviewer_not_approved}
      nil -> {:error, :reviewer_not_approved}
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  defp body_request_id_matches?(request_id, attrs) do
    case optional_binary(attrs, "request_id") do
      nil -> true
      ^request_id -> true
      _ -> false
    end
  end

  defp capsule_review_outcome_attrs(decision, review_node_id) do
    base =
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

    base
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
             tx_hash: "0x" <> random_hex(64),
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

  defp maybe_expire_orcid_request(%OrcidLinkRequest{} = request) do
    if request.state == "pending" and
         DateTime.compare(request.expires_at, DateTime.utc_now()) == :lt do
      {:ok, updated} =
        request
        |> OrcidLinkRequest.changeset(%{state: "expired"})
        |> Repo.update()

      updated
    else
      request
    end
  end

  defp required_wallet(agent_claims) do
    case Map.get(agent_claims || %{}, "wallet_address") do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "wallet_address is required"
    end
  end

  defp unique_suffix do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string(36)
  end

  defp draft_capsule_id do
    "capsule_draft_" <> unique_suffix()
  end

  defp random_hex(length) do
    bytes = div(length + 1, 2)

    Base.encode16(:crypto.strong_rand_bytes(bytes), case: :lower)
    |> binary_part(0, length)
  end

  defp generated_orcid_id(wallet_address) do
    digits =
      wallet_address
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> String.replace(~r/[^0-9]/, "")
      |> Kernel.<>("0000000000000000")
      |> binary_part(0, 16)

    [
      binary_part(digits, 0, 4),
      binary_part(digits, 4, 4),
      binary_part(digits, 8, 4),
      binary_part(digits, 12, 4)
    ]
    |> Enum.join("-")
  end

  defp required_binary(attrs, key) do
    case fetch_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_binary(attrs, key) do
    case fetch_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp required_map(attrs, key) do
    case fetch_value(attrs, key) do
      value when is_map(value) -> value
      _ -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_map(attrs, key) do
    case fetch_value(attrs, key) do
      value when is_map(value) -> value
      _ -> nil
    end
  end

  defp fetch_value(attrs, key) when is_map(attrs) and is_binary(key) do
    try do
      case Map.fetch(attrs, key) do
        {:ok, value} ->
          value

        :error ->
          atom_key = String.to_existing_atom(key)
          Map.get(attrs, atom_key)
      end
    rescue
      ArgumentError -> nil
    end
  end
end
