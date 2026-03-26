defmodule TechTree.Repo.Migrations.CutoverBbhAssignmentPolicies do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE bbh_capsules
    SET assignment_policy = CASE
      WHEN assignment_policy IN ('public_next', 'operator_assigned', 'validator_assigned') THEN 'auto_or_select'
      WHEN assignment_policy = 'draft_only' THEN 'operator'
      ELSE assignment_policy
    END
    """)

    execute("""
    UPDATE bbh_assignments
    SET origin = CASE
      WHEN origin IN ('public_next', 'operator_assigned', 'validator_assigned') THEN 'auto_or_select:auto'
      WHEN origin = 'draft_only' THEN 'operator:auto'
      ELSE origin
    END
    """)
  end

  def down do
    execute("""
    UPDATE bbh_capsules
    SET assignment_policy = CASE
      WHEN assignment_policy = 'auto_or_select' THEN 'public_next'
      WHEN assignment_policy = 'operator' THEN 'draft_only'
      ELSE assignment_policy
    END
    """)

    execute("""
    UPDATE bbh_assignments
    SET origin = CASE
      WHEN origin = 'auto_or_select:auto' THEN 'public_next'
      WHEN origin = 'operator:auto' THEN 'draft_only'
      ELSE origin
    END
    """)
  end
end
