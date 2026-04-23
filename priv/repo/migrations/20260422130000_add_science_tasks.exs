defmodule TechTree.Repo.Migrations.AddScienceTasks do
  use Ecto.Migration

  def change do
    create table(:science_tasks) do
      add :node_id, references(:nodes, on_delete: :delete_all), null: false
      add :science_domain, :text, null: false
      add :science_field, :text, null: false
      add :task_slug, :text, null: false
      add :structured_output_shape, :map
      add :claimed_expert_time, :text, null: false
      add :threshold_rationale, :text
      add :anti_cheat_notes, :text, null: false
      add :reproducibility_notes, :text, null: false
      add :dependency_pinning_status, :text, null: false
      add :canary_status, :text, null: false
      add :destination_name, :text, null: false, default: "terminal-bench-science"
      add :packet_hash, :text, null: false
      add :evidence_packet_hash, :text
      add :packet_files, :map, null: false, default: %{}
      add :checklist, :map, null: false, default: %{}
      add :oracle_run, :map
      add :frontier_run, :map
      add :failure_analysis, :text, null: false
      add :harbor_pr_url, :text
      add :review_round_count, :integer, null: false, default: 0
      add :open_reviewer_concerns_count, :integer, null: false, default: 0
      add :latest_rerun_after_latest_fix, :boolean, null: false, default: false
      add :latest_review_follow_up_note, :text
      add :last_rerun_at, :utc_datetime_usec
      add :latest_fix_at, :utc_datetime_usec
      add :any_concern_unanswered, :boolean, null: false, default: false
      add :workflow_state, :text, null: false, default: "authoring"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:science_tasks, [:node_id])
    create unique_index(:science_tasks, [:science_domain, :science_field, :task_slug])
    create index(:science_tasks, [:workflow_state])
    create index(:science_tasks, [:science_domain])
    create index(:science_tasks, [:science_field])
  end
end
