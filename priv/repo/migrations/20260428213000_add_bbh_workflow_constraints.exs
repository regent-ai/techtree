defmodule TechTree.Repo.Migrations.AddBbhWorkflowConstraints do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE bbh_capsules
    ADD CONSTRAINT bbh_capsules_workflow_state_check
    CHECK (workflow_state IN ('authoring', 'review_ready', 'in_review', 'approved', 'rejected')) NOT VALID
    """)

    execute("""
    ALTER TABLE bbh_capsules
    ADD CONSTRAINT bbh_capsules_certificate_status_check
    CHECK (certificate_status IN ('none', 'active')) NOT VALID
    """)

    execute("""
    ALTER TABLE bbh_assignments
    ADD CONSTRAINT bbh_assignments_status_check
    CHECK (status IN ('assigned', 'completed')) NOT VALID
    """)

    execute("""
    ALTER TABLE bbh_runs
    ADD CONSTRAINT bbh_runs_status_check
    CHECK (status IN ('validation_pending', 'running', 'failed', 'validated', 'rejected')) NOT VALID
    """)

    execute("""
    ALTER TABLE bbh_validations
    ADD CONSTRAINT bbh_validations_role_check
    CHECK (role IN ('official', 'community')) NOT VALID
    """)

    execute("""
    ALTER TABLE bbh_validations
    ADD CONSTRAINT bbh_validations_method_check
    CHECK (method IN ('replay', 'manual', 'replication')) NOT VALID
    """)

    execute("""
    ALTER TABLE bbh_validations
    ADD CONSTRAINT bbh_validations_result_check
    CHECK (result IN ('confirmed', 'rejected', 'mixed', 'needs_revision')) NOT VALID
    """)

    execute("""
    ALTER TABLE bbh_draft_proposals
    ADD CONSTRAINT bbh_draft_proposals_status_check
    CHECK (status IN ('open', 'accepted')) NOT VALID
    """)

    execute("""
    ALTER TABLE bbh_reviewer_profiles
    ADD CONSTRAINT bbh_reviewer_profiles_vetting_status_check
    CHECK (vetting_status IN ('pending', 'approved', 'rejected')) NOT VALID
    """)

    execute("""
    ALTER TABLE bbh_orcid_link_requests
    ADD CONSTRAINT bbh_orcid_link_requests_state_check
    CHECK (state IN ('pending', 'authenticated', 'expired')) NOT VALID
    """)

    execute("""
    ALTER TABLE bbh_review_requests
    ADD CONSTRAINT bbh_review_requests_review_kind_check
    CHECK (review_kind IN ('design', 'genome', 'certification')) NOT VALID
    """)

    execute("""
    ALTER TABLE bbh_review_requests
    ADD CONSTRAINT bbh_review_requests_visibility_check
    CHECK (visibility IN ('public_claim')) NOT VALID
    """)

    execute("""
    ALTER TABLE bbh_review_requests
    ADD CONSTRAINT bbh_review_requests_state_check
    CHECK (state IN ('open', 'claimed', 'closed')) NOT VALID
    """)

    execute("""
    ALTER TABLE bbh_review_submissions
    ADD CONSTRAINT bbh_review_submissions_decision_check
    CHECK (decision IN ('approve', 'approve_with_edits', 'changes_requested', 'reject')) NOT VALID
    """)
  end

  def down do
    raise "hard cutover only"
  end
end
