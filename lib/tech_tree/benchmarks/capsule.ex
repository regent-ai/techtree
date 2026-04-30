defmodule TechTree.Benchmarks.Capsule do
  @moduledoc false
  use TechTree.Schema

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Benchmarks.{Artifact, Attempt, CapsuleVersion, ReliabilitySummary, Validation}
  alias TechTree.Nodes.Node

  @domains [
    :bbh,
    :bioinformatics,
    :computational_biology,
    :science_task,
    :code,
    :math,
    :agent_skill,
    :other
  ]

  @human_baseline_statuses [
    :unknown,
    :human_solvable,
    :human_difficult,
    :expert_only,
    :unsolved,
    :not_applicable
  ]

  @ground_truth_policies [
    :public,
    :hidden_server,
    :reviewer_only,
    :deterministic_oracle,
    :external_oracle,
    :metadata_scrambled,
    :synthetic
  ]

  @workflow_states [
    :authoring,
    :review_ready,
    :in_review,
    :approved,
    :published,
    :rejected,
    :retired
  ]

  @visibilities [:draft, :private_review, :public, :paid_access]

  @primary_key {:capsule_id, :string, autogenerate: false}
  @foreign_key_type :string

  @type t :: %__MODULE__{}

  schema "benchmark_capsules" do
    field :legacy_bbh_capsule_id, :string
    field :owner_wallet_address, :string
    field :domain, Ecto.Enum, values: @domains
    field :field, :string
    field :family_ref, :string
    field :provider, :string
    field :provider_ref, :string
    field :import_batch_id, :string
    field :title, :string
    field :summary_md, :string
    field :question_md, :string
    field :difficulty_label, :string
    field :human_baseline_status, Ecto.Enum, values: @human_baseline_statuses, default: :unknown
    field :ground_truth_policy, Ecto.Enum, values: @ground_truth_policies
    field :answer_format, :map, default: %{}
    field :allowed_tools_policy, :map, default: %{}
    field :external_resource_policy, :map, default: %{}
    field :scoring_policy, :map, default: %{}
    field :anti_cheat_policy, :map, default: %{}
    field :workflow_state, Ecto.Enum, values: @workflow_states, default: :authoring
    field :visibility, Ecto.Enum, values: @visibilities, default: :draft
    field :current_version_id, :string
    field :published_at, :utc_datetime_usec
    field :retired_at, :utc_datetime_usec

    belongs_to :source_node, Node, type: :id
    belongs_to :owner_agent, AgentIdentity, type: :id

    has_many :versions, CapsuleVersion,
      foreign_key: :capsule_id,
      references: :capsule_id

    has_many :attempts, Attempt,
      foreign_key: :capsule_id,
      references: :capsule_id

    has_many :validations, Validation,
      foreign_key: :capsule_id,
      references: :capsule_id

    has_many :reliability_summaries, ReliabilitySummary,
      foreign_key: :capsule_id,
      references: :capsule_id

    has_many :artifacts, Artifact,
      foreign_key: :capsule_id,
      references: :capsule_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(capsule, attrs) do
    capsule
    |> cast(attrs, [
      :capsule_id,
      :legacy_bbh_capsule_id,
      :source_node_id,
      :owner_agent_id,
      :owner_wallet_address,
      :domain,
      :field,
      :family_ref,
      :provider,
      :provider_ref,
      :import_batch_id,
      :title,
      :summary_md,
      :question_md,
      :difficulty_label,
      :human_baseline_status,
      :ground_truth_policy,
      :answer_format,
      :allowed_tools_policy,
      :external_resource_policy,
      :scoring_policy,
      :anti_cheat_policy,
      :workflow_state,
      :visibility,
      :current_version_id,
      :published_at,
      :retired_at
    ])
    |> validate_required([
      :capsule_id,
      :domain,
      :title,
      :question_md,
      :human_baseline_status,
      :ground_truth_policy,
      :answer_format,
      :allowed_tools_policy,
      :external_resource_policy,
      :scoring_policy,
      :anti_cheat_policy,
      :workflow_state,
      :visibility
    ])
    |> unique_constraint(:legacy_bbh_capsule_id)
    |> foreign_key_constraint(:source_node_id)
    |> foreign_key_constraint(:owner_agent_id)
    |> check_constraint(:domain, name: :benchmark_capsules_domain_check)
    |> check_constraint(:human_baseline_status,
      name: :benchmark_capsules_human_baseline_status_check
    )
    |> check_constraint(:ground_truth_policy,
      name: :benchmark_capsules_ground_truth_policy_check
    )
    |> check_constraint(:workflow_state, name: :benchmark_capsules_workflow_state_check)
    |> check_constraint(:visibility, name: :benchmark_capsules_visibility_check)
  end

  @spec domains() :: [atom()]
  def domains, do: @domains

  @spec workflow_states() :: [atom()]
  def workflow_states, do: @workflow_states
end
