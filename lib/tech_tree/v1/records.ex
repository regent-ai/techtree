defmodule TechTree.V1.Node do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "manifest_nodes" do
    field :node_type, :integer
    field :author, :string
    field :subject_id, :string
    field :aux_id, :string
    field :payload_hash, :string
    field :manifest_cid, :string
    field :payload_cid, :string
    field :schema_version, :integer
    field :tx_hash, :string
    field :block_number, :integer
    field :block_time, :utc_datetime_usec
    field :verification_status, :string, default: "verified"
    field :verification_error, :string
    field :header, :map, default: %{}
    field :manifest, :map, default: %{}
    field :payload_index, :map, default: %{}

    has_one :artifact, TechTree.V1.Artifact, foreign_key: :id
    has_one :run, TechTree.V1.Run, foreign_key: :id
    has_one :review, TechTree.V1.Review, foreign_key: :id
    has_one :state, TechTree.V1.NodeState, foreign_key: :node_id
    has_many :payload_files, TechTree.V1.PayloadFile, foreign_key: :node_id

    timestamps()
  end

  def changeset(node, attrs) do
    node
    |> cast(attrs, [
      :id,
      :node_type,
      :author,
      :subject_id,
      :aux_id,
      :payload_hash,
      :manifest_cid,
      :payload_cid,
      :schema_version,
      :tx_hash,
      :block_number,
      :block_time,
      :verification_status,
      :verification_error,
      :header,
      :manifest,
      :payload_index
    ])
    |> validate_required([
      :id,
      :node_type,
      :author,
      :payload_hash,
      :schema_version,
      :verification_status,
      :header,
      :manifest,
      :payload_index
    ])
  end
end

defmodule TechTree.V1.Artifact do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "manifest_artifacts" do
    field :kind, :string
    field :title, :string
    field :summary, :string
    field :has_eval, :boolean, default: false
    field :eval_mode, :string

    belongs_to :node, TechTree.V1.Node,
      define_field: false,
      foreign_key: :id,
      references: :id,
      type: :string

    timestamps()
  end

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [:id, :kind, :title, :summary, :has_eval, :eval_mode])
    |> validate_required([:id, :kind, :title, :summary, :has_eval])
  end
end

defmodule TechTree.V1.ArtifactEdge do
  @moduledoc false
  use TechTree.Schema

  @foreign_key_type :string

  schema "manifest_artifact_edges" do
    field :relation, :string
    field :note, :string

    belongs_to :child, TechTree.V1.Node, foreign_key: :child_id, references: :id, type: :string
    belongs_to :parent, TechTree.V1.Node, foreign_key: :parent_id, references: :id, type: :string

    timestamps(updated_at: false)
  end

  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [:child_id, :parent_id, :relation, :note])
    |> validate_required([:child_id, :parent_id, :relation])
  end
end

defmodule TechTree.V1.Run do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "manifest_runs" do
    field :artifact_id, :string
    field :executor_type, :string
    field :executor_id, :string
    field :executor_harness_kind, :string
    field :executor_harness_profile, :string
    field :origin_kind, :string
    field :origin_transport, :string
    field :origin_session_id, :string
    field :status, :string
    field :score, :float

    belongs_to :node, TechTree.V1.Node,
      define_field: false,
      foreign_key: :id,
      references: :id,
      type: :string

    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :id,
      :artifact_id,
      :executor_type,
      :executor_id,
      :executor_harness_kind,
      :executor_harness_profile,
      :origin_kind,
      :origin_transport,
      :origin_session_id,
      :status,
      :score
    ])
    |> validate_required([:id, :artifact_id, :executor_type, :executor_id, :status])
  end
end

defmodule TechTree.V1.Review do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "manifest_reviews" do
    field :target_type, :string
    field :target_id, :string
    field :kind, :string
    field :method, :string
    field :result, :string
    field :scope_level, :string
    field :scope_path, :string

    belongs_to :node, TechTree.V1.Node,
      define_field: false,
      foreign_key: :id,
      references: :id,
      type: :string

    timestamps()
  end

  def changeset(review, attrs) do
    review
    |> cast(attrs, [
      :id,
      :target_type,
      :target_id,
      :kind,
      :method,
      :result,
      :scope_level,
      :scope_path
    ])
    |> validate_required([:id, :target_type, :target_id, :kind, :method, :result, :scope_level])
  end
end

defmodule TechTree.V1.PayloadFile do
  @moduledoc false
  use TechTree.Schema

  @foreign_key_type :string

  schema "manifest_payload_files" do
    field :path, :string
    field :sha256, :string
    field :size, :integer
    field :media_type, :string
    field :role, :string

    belongs_to :node, TechTree.V1.Node, foreign_key: :node_id, references: :id, type: :string

    timestamps(updated_at: false)
  end

  def changeset(payload_file, attrs) do
    payload_file
    |> cast(attrs, [:node_id, :path, :sha256, :size, :media_type, :role])
    |> validate_required([:node_id, :path, :sha256, :size, :media_type, :role])
  end
end

defmodule TechTree.V1.Source do
  @moduledoc false
  use TechTree.Schema

  @foreign_key_type :string

  schema "manifest_sources" do
    field :ordinal, :integer
    field :kind, :string
    field :ref, :string
    field :license, :string
    field :note, :string

    belongs_to :node, TechTree.V1.Node, foreign_key: :node_id, references: :id, type: :string

    timestamps(updated_at: false)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:node_id, :ordinal, :kind, :ref, :license, :note])
    |> validate_required([:node_id, :ordinal, :kind, :ref])
  end
end

defmodule TechTree.V1.Claim do
  @moduledoc false
  use TechTree.Schema

  @foreign_key_type :string

  schema "manifest_claims" do
    field :ordinal, :integer
    field :text, :string

    belongs_to :artifact, TechTree.V1.Node,
      foreign_key: :artifact_id,
      references: :id,
      type: :string

    timestamps(updated_at: false)
  end

  def changeset(claim, attrs) do
    claim
    |> cast(attrs, [:artifact_id, :ordinal, :text])
    |> validate_required([:artifact_id, :ordinal, :text])
  end
end

defmodule TechTree.V1.Finding do
  @moduledoc false
  use TechTree.Schema

  @foreign_key_type :string

  schema "manifest_findings" do
    field :ordinal, :integer
    field :code, :string
    field :severity, :string
    field :message, :string

    belongs_to :review, TechTree.V1.Node, foreign_key: :review_id, references: :id, type: :string

    timestamps(updated_at: false)
  end

  def changeset(finding, attrs) do
    finding
    |> cast(attrs, [:review_id, :ordinal, :code, :severity, :message])
    |> validate_required([:review_id, :ordinal, :code, :severity, :message])
  end
end

defmodule TechTree.V1.NodeState do
  @moduledoc false
  use TechTree.Schema

  @primary_key false
  @foreign_key_type :string

  schema "manifest_node_state" do
    field :validated, :boolean, default: false
    field :challenged, :boolean, default: false
    field :retired, :boolean, default: false
    field :latest_review_result, :string

    belongs_to :node, TechTree.V1.Node,
      primary_key: true,
      foreign_key: :node_id,
      references: :id,
      type: :string

    timestamps()
  end

  def changeset(node_state, attrs) do
    node_state
    |> cast(attrs, [:node_id, :validated, :challenged, :retired, :latest_review_result])
    |> validate_required([:node_id, :validated, :challenged, :retired])
  end
end

defmodule TechTree.V1.RejectedIngest do
  @moduledoc false
  use TechTree.Schema

  schema "manifest_rejected_ingests" do
    field :node_id, :string
    field :node_type, :integer
    field :manifest_cid, :string
    field :payload_cid, :string
    field :reason, :string
    field :header, :map, default: %{}
    field :manifest, :map, default: %{}
    field :payload_index, :map, default: %{}

    timestamps(updated_at: false)
  end

  def changeset(rejected_ingest, attrs) do
    rejected_ingest
    |> cast(attrs, [
      :node_id,
      :node_type,
      :manifest_cid,
      :payload_cid,
      :reason,
      :header,
      :manifest,
      :payload_index
    ])
    |> validate_required([:reason, :header, :manifest, :payload_index])
  end
end
