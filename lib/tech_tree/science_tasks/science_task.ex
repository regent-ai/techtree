defmodule TechTree.ScienceTasks.ScienceTask do
  @moduledoc false
  use TechTree.Schema

  alias TechTree.Nodes.Node

  @workflow_states [
    :authoring,
    :checklist_fix,
    :evidence_ready,
    :submitted,
    :review_fix,
    :merge_ready
  ]

  @type t :: %__MODULE__{
          id: integer() | nil,
          node_id: integer() | nil,
          science_domain: String.t() | nil,
          science_field: String.t() | nil,
          task_slug: String.t() | nil,
          structured_output_shape: map() | nil,
          claimed_expert_time: String.t() | nil,
          threshold_rationale: String.t() | nil,
          anti_cheat_notes: String.t() | nil,
          reproducibility_notes: String.t() | nil,
          dependency_pinning_status: String.t() | nil,
          canary_status: String.t() | nil,
          destination_name: String.t() | nil,
          packet_hash: String.t() | nil,
          evidence_packet_hash: String.t() | nil,
          packet_files: map(),
          checklist: map(),
          oracle_run: map() | nil,
          frontier_run: map() | nil,
          failure_analysis: String.t() | nil,
          harbor_pr_url: String.t() | nil,
          review_round_count: integer(),
          open_reviewer_concerns_count: integer(),
          latest_rerun_after_latest_fix: boolean(),
          latest_review_follow_up_note: String.t() | nil,
          last_rerun_at: DateTime.t() | nil,
          latest_fix_at: DateTime.t() | nil,
          any_concern_unanswered: boolean(),
          workflow_state: atom() | nil
        }

  schema "science_tasks" do
    field :science_domain, :string
    field :science_field, :string
    field :task_slug, :string
    field :structured_output_shape, :map
    field :claimed_expert_time, :string
    field :threshold_rationale, :string
    field :anti_cheat_notes, :string
    field :reproducibility_notes, :string
    field :dependency_pinning_status, :string
    field :canary_status, :string
    field :destination_name, :string, default: "terminal-bench-science"
    field :packet_hash, :string
    field :evidence_packet_hash, :string
    field :packet_files, :map, default: %{}
    field :checklist, :map, default: %{}
    field :oracle_run, :map
    field :frontier_run, :map
    field :failure_analysis, :string
    field :harbor_pr_url, :string
    field :review_round_count, :integer, default: 0
    field :open_reviewer_concerns_count, :integer, default: 0
    field :latest_rerun_after_latest_fix, :boolean, default: false
    field :latest_review_follow_up_note, :string
    field :last_rerun_at, :utc_datetime_usec
    field :latest_fix_at, :utc_datetime_usec
    field :any_concern_unanswered, :boolean, default: false
    field :workflow_state, Ecto.Enum, values: @workflow_states, default: :authoring

    belongs_to :node, Node

    timestamps()
  end

  @spec workflow_states() :: [atom()]
  def workflow_states, do: @workflow_states

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :node_id,
      :science_domain,
      :science_field,
      :task_slug,
      :structured_output_shape,
      :claimed_expert_time,
      :threshold_rationale,
      :anti_cheat_notes,
      :reproducibility_notes,
      :dependency_pinning_status,
      :canary_status,
      :destination_name,
      :packet_hash,
      :evidence_packet_hash,
      :packet_files,
      :checklist,
      :oracle_run,
      :frontier_run,
      :failure_analysis,
      :harbor_pr_url,
      :review_round_count,
      :open_reviewer_concerns_count,
      :latest_rerun_after_latest_fix,
      :latest_review_follow_up_note,
      :last_rerun_at,
      :latest_fix_at,
      :any_concern_unanswered,
      :workflow_state
    ])
    |> validate_required([
      :node_id,
      :science_domain,
      :science_field,
      :task_slug,
      :claimed_expert_time,
      :anti_cheat_notes,
      :reproducibility_notes,
      :dependency_pinning_status,
      :canary_status,
      :packet_hash,
      :packet_files,
      :checklist,
      :failure_analysis,
      :workflow_state
    ])
    |> validate_number(:review_round_count, greater_than_or_equal_to: 0)
    |> validate_number(:open_reviewer_concerns_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:node_id)
    |> unique_constraint([:science_domain, :science_field, :task_slug])
    |> foreign_key_constraint(:node_id)
  end
end
