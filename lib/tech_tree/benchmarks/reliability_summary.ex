defmodule TechTree.Benchmarks.ReliabilitySummary do
  @moduledoc false
  use TechTree.Schema

  alias TechTree.Benchmarks.{Capsule, CapsuleVersion, Harness}

  @primary_key {:summary_id, :string, autogenerate: false}
  @foreign_key_type :string

  @type t :: %__MODULE__{}

  schema "benchmark_reliability_summaries" do
    field :capsule_id, :string
    field :version_id, :string
    field :harness_id, :string
    field :repeat_group_id, :string
    field :attempt_count, :integer, default: 0
    field :solve_count, :integer, default: 0
    field :solve_rate, :float, default: 0.0
    field :reliable, :boolean, default: false
    field :brittle, :boolean, default: false
    field :answer_variance, :map, default: %{}
    field :median_runtime_seconds, :float
    field :p90_runtime_seconds, :float
    field :median_cost_usd_micros, :integer
    field :validation_confirmed_count, :integer, default: 0
    field :last_attempt_at, :utc_datetime_usec

    belongs_to :capsule, Capsule,
      define_field: false,
      foreign_key: :capsule_id,
      references: :capsule_id,
      type: :string

    belongs_to :version, CapsuleVersion,
      define_field: false,
      foreign_key: :version_id,
      references: :version_id,
      type: :string

    belongs_to :harness, Harness,
      define_field: false,
      foreign_key: :harness_id,
      references: :harness_id,
      type: :string

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [
      :summary_id,
      :capsule_id,
      :version_id,
      :harness_id,
      :repeat_group_id,
      :attempt_count,
      :solve_count,
      :solve_rate,
      :reliable,
      :brittle,
      :answer_variance,
      :median_runtime_seconds,
      :p90_runtime_seconds,
      :median_cost_usd_micros,
      :validation_confirmed_count,
      :last_attempt_at
    ])
    |> validate_required([
      :summary_id,
      :capsule_id,
      :version_id,
      :harness_id,
      :repeat_group_id,
      :attempt_count,
      :solve_count,
      :solve_rate,
      :reliable,
      :brittle,
      :answer_variance,
      :validation_confirmed_count
    ])
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
    |> validate_number(:solve_count, greater_than_or_equal_to: 0)
    |> validate_number(:solve_rate, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:validation_confirmed_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:capsule_id, :version_id, :harness_id, :repeat_group_id])
    |> foreign_key_constraint(:capsule_id)
    |> foreign_key_constraint(:version_id)
    |> foreign_key_constraint(:harness_id)
  end
end
