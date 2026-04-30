defmodule TechTree.Benchmarks.Harness do
  @moduledoc false
  use TechTree.Schema

  alias TechTree.Agents.AgentIdentity
  alias TechTree.Benchmarks.{Attempt, ReliabilitySummary}

  @runner_kinds [
    :hermes,
    :openclaw,
    :regents,
    :codex,
    :claude,
    :skydiscover,
    :gemini,
    :opencode,
    :manual_human,
    :custom_local
  ]

  @primary_key {:harness_id, :string, autogenerate: false}
  @foreign_key_type :string

  @type t :: %__MODULE__{}

  schema "benchmark_harnesses" do
    field :name, :string
    field :description_md, :string
    field :domain, :string
    field :runner_kind, Ecto.Enum, values: @runner_kinds
    field :model_id, :string
    field :agent_runtime, :string
    field :harness_version, :string
    field :prompt_pack_ref, :map, default: %{}
    field :skill_pack_refs, {:array, :map}, default: []
    field :tool_profile, :map, default: %{}
    field :runtime_image, :string
    field :dependency_lock_ref, :map, default: %{}
    field :workspace_policy, :map, default: %{}
    field :normalized_bundle_hash, :string
    field :source, :map, default: %{}

    belongs_to :owner_agent, AgentIdentity, type: :id

    has_many :attempts, Attempt,
      foreign_key: :harness_id,
      references: :harness_id

    has_many :reliability_summaries, ReliabilitySummary,
      foreign_key: :harness_id,
      references: :harness_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(harness, attrs) do
    harness
    |> cast(attrs, [
      :harness_id,
      :owner_agent_id,
      :name,
      :description_md,
      :domain,
      :runner_kind,
      :model_id,
      :agent_runtime,
      :harness_version,
      :prompt_pack_ref,
      :skill_pack_refs,
      :tool_profile,
      :runtime_image,
      :dependency_lock_ref,
      :workspace_policy,
      :normalized_bundle_hash,
      :source
    ])
    |> validate_required([
      :harness_id,
      :name,
      :runner_kind,
      :harness_version,
      :prompt_pack_ref,
      :skill_pack_refs,
      :tool_profile,
      :dependency_lock_ref,
      :workspace_policy,
      :normalized_bundle_hash,
      :source
    ])
    |> unique_constraint(:normalized_bundle_hash)
    |> foreign_key_constraint(:owner_agent_id)
    |> check_constraint(:runner_kind, name: :benchmark_harnesses_runner_kind_check)
  end

  @spec runner_kinds() :: [atom()]
  def runner_kinds, do: @runner_kinds
end
