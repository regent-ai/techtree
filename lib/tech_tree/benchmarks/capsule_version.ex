defmodule TechTree.Benchmarks.CapsuleVersion do
  @moduledoc false
  use TechTree.Schema

  alias TechTree.Benchmarks.{Artifact, Attempt, Capsule, ReliabilitySummary}
  alias TechTree.Nodes.Node

  @statuses [:draft, :review_ready, :approved, :published, :superseded, :retired]

  @primary_key {:version_id, :string, autogenerate: false}
  @foreign_key_type :string

  @type t :: %__MODULE__{}

  schema "benchmark_capsule_versions" do
    field :capsule_id, :string
    field :version_label, :string
    field :version_status, Ecto.Enum, values: @statuses, default: :draft
    field :manifest_cid, :string
    field :manifest_sha256, :string
    field :manifest_uri, :string
    field :input_bundle_cid, :string
    field :input_bundle_sha256, :string
    field :validation_notebook_cid, :string
    field :validation_notebook_sha256, :string
    field :redacted_validation_notebook_cid, :string
    field :ground_truth_manifest_hash, :string
    field :ground_truth_storage_policy, :map, default: %{}
    field :environment_lock_ref, :map, default: %{}
    field :data_manifest, :map, default: %{}
    field :capsule_source, :map, default: %{}
    field :chain_tx_hash, :string
    field :chain_id, :integer
    field :anchored_at, :utc_datetime_usec

    belongs_to :capsule, Capsule,
      define_field: false,
      foreign_key: :capsule_id,
      references: :capsule_id,
      type: :string

    belongs_to :publication_node, Node, type: :id

    has_many :attempts, Attempt,
      foreign_key: :version_id,
      references: :version_id

    has_many :reliability_summaries, ReliabilitySummary,
      foreign_key: :version_id,
      references: :version_id

    has_many :artifacts, Artifact,
      foreign_key: :version_id,
      references: :version_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(version, attrs) do
    version
    |> cast(attrs, [
      :version_id,
      :capsule_id,
      :version_label,
      :version_status,
      :manifest_cid,
      :manifest_sha256,
      :manifest_uri,
      :input_bundle_cid,
      :input_bundle_sha256,
      :validation_notebook_cid,
      :validation_notebook_sha256,
      :redacted_validation_notebook_cid,
      :ground_truth_manifest_hash,
      :ground_truth_storage_policy,
      :environment_lock_ref,
      :data_manifest,
      :capsule_source,
      :publication_node_id,
      :chain_tx_hash,
      :chain_id,
      :anchored_at
    ])
    |> validate_required([
      :version_id,
      :capsule_id,
      :version_label,
      :version_status,
      :ground_truth_storage_policy,
      :environment_lock_ref,
      :data_manifest,
      :capsule_source
    ])
    |> unique_constraint([:capsule_id, :version_label])
    |> foreign_key_constraint(:capsule_id)
    |> foreign_key_constraint(:publication_node_id)
    |> check_constraint(:version_status, name: :benchmark_capsule_versions_status_check)
  end

  @spec statuses() :: [atom()]
  def statuses, do: @statuses
end
