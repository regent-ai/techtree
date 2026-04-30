defmodule TechTree.Benchmarks.Artifact do
  @moduledoc false
  use TechTree.Schema

  alias TechTree.Benchmarks.{Attempt, Capsule, CapsuleVersion, Validation}

  @kinds [
    :input_bundle,
    :data_manifest,
    :validation_notebook,
    :redacted_validation_notebook,
    :ground_truth_manifest,
    :run_bundle,
    :solver_notebook,
    :tool_calls_log,
    :run_log,
    :report,
    :review_packet,
    :skill_bundle,
    :harness_bundle
  ]

  @visibilities [:public, :paid, :reviewer_only, :private]

  @primary_key {:artifact_id, :string, autogenerate: false}
  @foreign_key_type :string

  @type t :: %__MODULE__{}

  schema "benchmark_artifacts" do
    field :capsule_id, :string
    field :version_id, :string
    field :attempt_id, :string
    field :validation_id, :string
    field :kind, Ecto.Enum, values: @kinds
    field :name, :string
    field :cid, :string
    field :uri, :string
    field :sha256, :string
    field :byte_size, :integer
    field :content_type, :string
    field :storage_provider, :string, default: "lighthouse"
    field :visibility, Ecto.Enum, values: @visibilities, default: :public
    field :encryption_meta, :map, default: %{}
    field :license, :string

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

    belongs_to :attempt, Attempt,
      define_field: false,
      foreign_key: :attempt_id,
      references: :attempt_id,
      type: :string

    belongs_to :validation, Validation,
      define_field: false,
      foreign_key: :validation_id,
      references: :validation_id,
      type: :string

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [
      :artifact_id,
      :capsule_id,
      :version_id,
      :attempt_id,
      :validation_id,
      :kind,
      :name,
      :cid,
      :uri,
      :sha256,
      :byte_size,
      :content_type,
      :storage_provider,
      :visibility,
      :encryption_meta,
      :license
    ])
    |> validate_required([:artifact_id, :kind, :storage_provider, :visibility, :encryption_meta])
    |> validate_number(:byte_size, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:capsule_id)
    |> foreign_key_constraint(:version_id)
    |> foreign_key_constraint(:attempt_id)
    |> foreign_key_constraint(:validation_id)
    |> check_constraint(:kind, name: :benchmark_artifacts_kind_check)
    |> check_constraint(:visibility, name: :benchmark_artifacts_visibility_check)
  end

  @spec kinds() :: [atom()]
  def kinds, do: @kinds

  @spec visibilities() :: [atom()]
  def visibilities, do: @visibilities
end
