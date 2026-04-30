defmodule TechTree.BBH do
  @moduledoc false

  defdelegate next_assignment(agent_claims, attrs \\ %{}), to: TechTree.BBH.Assignments
  defdelegate select_assignment(agent_claims, attrs), to: TechTree.BBH.Assignments

  defdelegate create_run(attrs), to: TechTree.BBH.RunIngest
  defdelegate create_validation(attrs), to: TechTree.BBH.RunIngest

  defdelegate sync_status(run_ids), to: TechTree.BBH.RunReads
  defdelegate leaderboard(opts \\ %{}), to: TechTree.Benchmarks.Domains.BBH

  defdelegate list_runs(opts \\ %{}), to: TechTree.Benchmarks.Domains.BBH
  defdelegate list_capsules(opts \\ %{}), to: TechTree.Benchmarks.Domains.BBH
  defdelegate list_public_capsules(opts \\ %{}), to: TechTree.Benchmarks.Domains.BBH
  defdelegate get_public_capsule(capsule_id), to: TechTree.Benchmarks.Domains.BBH
  defdelegate get_run(run_id), to: TechTree.Benchmarks.Domains.BBH
  defdelegate get_genome(genome_id), to: TechTree.Benchmarks.Domains.BBH
  defdelegate list_validations(run_id), to: TechTree.Benchmarks.Domains.BBH

  defdelegate create_draft(agent_claims, attrs), to: TechTree.BBH.Drafts
  defdelegate list_drafts(agent_claims), to: TechTree.BBH.Drafts
  defdelegate get_draft(capsule_id), to: TechTree.BBH.Drafts
  defdelegate create_draft_proposal(agent_claims, capsule_id, attrs), to: TechTree.BBH.Drafts
  defdelegate list_draft_proposals(capsule_id), to: TechTree.BBH.Drafts
  defdelegate apply_draft_proposal(capsule_id, proposal_id), to: TechTree.BBH.Drafts
  defdelegate ready_draft(agent_claims, capsule_id), to: TechTree.BBH.Drafts

  defdelegate start_reviewer_orcid_link(agent_claims), to: TechTree.BBH.Reviewers

  defdelegate get_reviewer_orcid_link_status(agent_claims, request_id),
    to: TechTree.BBH.Reviewers

  defdelegate apply_reviewer(agent_claims, attrs), to: TechTree.BBH.Reviewers
  defdelegate get_reviewer(agent_claims), to: TechTree.BBH.Reviewers
  defdelegate approve_reviewer(wallet_address, admin_ref, status), to: TechTree.BBH.Reviewers
  defdelegate complete_orcid_link(request_id), to: TechTree.BBH.Reviewers

  defdelegate list_reviews(agent_claims, attrs \\ %{}), to: TechTree.BBH.Reviews
  defdelegate claim_review(agent_claims, request_id), to: TechTree.BBH.Reviews
  defdelegate get_review_packet(agent_claims, request_id), to: TechTree.BBH.Reviews
  defdelegate submit_review(agent_claims, request_id, attrs), to: TechTree.BBH.Reviews

  defdelegate certificate_summary(capsule_id), to: TechTree.Benchmarks.Domains.BBH
  defdelegate review_open_count(capsule_id), to: TechTree.Benchmarks.Domains.BBH

  defdelegate upsert_capsule(attrs), to: TechTree.BBH.Inventory
  defdelegate promote_challenge_capsule(capsule_id, attrs), to: TechTree.BBH.Inventory
end
