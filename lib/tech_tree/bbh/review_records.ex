defmodule TechTree.BBH.DraftProposal do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:proposal_id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "bbh_draft_proposals" do
    field :capsule_id, :string
    field :proposer_wallet_address, :string
    field :summary, :string
    field :workspace_bundle, :map, default: %{}
    field :patch_json, :map, default: %{}
    field :workspace_manifest_hash, :string
    field :status, :string, default: "open"

    belongs_to :capsule, TechTree.BBH.Capsule,
      define_field: false,
      foreign_key: :capsule_id,
      references: :capsule_id,
      type: :string

    timestamps()
  end

  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, [
      :proposal_id,
      :capsule_id,
      :proposer_wallet_address,
      :summary,
      :workspace_bundle,
      :patch_json,
      :workspace_manifest_hash,
      :status
    ])
    |> validate_required([
      :proposal_id,
      :capsule_id,
      :proposer_wallet_address,
      :summary,
      :workspace_bundle,
      :workspace_manifest_hash,
      :status
    ])
  end
end

defmodule TechTree.BBH.ReviewerProfile do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:wallet_address, :string, autogenerate: false}

  schema "bbh_reviewer_profiles" do
    field :orcid_id, :string
    field :orcid_auth_kind, :string
    field :orcid_name, :string
    field :vetting_status, :string, default: "pending"
    field :domain_tags, {:array, :string}, default: []
    field :payout_wallet, :string
    field :experience_summary, :string
    field :vetted_by, :string
    field :vetted_at, :utc_datetime_usec

    timestamps()
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :wallet_address,
      :orcid_id,
      :orcid_auth_kind,
      :orcid_name,
      :vetting_status,
      :domain_tags,
      :payout_wallet,
      :experience_summary,
      :vetted_by,
      :vetted_at
    ])
    |> validate_required([:wallet_address, :vetting_status, :domain_tags])
  end
end

defmodule TechTree.BBH.OrcidLinkRequest do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:request_id, :string, autogenerate: false}

  schema "bbh_orcid_link_requests" do
    field :wallet_address, :string
    field :state, :string, default: "pending"
    field :expires_at, :utc_datetime_usec
    field :authenticated_at, :utc_datetime_usec

    timestamps()
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [:request_id, :wallet_address, :state, :expires_at, :authenticated_at])
    |> validate_required([:request_id, :wallet_address, :state, :expires_at])
  end
end

defmodule TechTree.BBH.ReviewRequest do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:request_id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "bbh_review_requests" do
    field :capsule_id, :string
    field :review_kind, :string
    field :visibility, :string, default: "public_claim"
    field :state, :string, default: "open"
    field :claimed_by_wallet, :string
    field :fee_quote_usdc, :string
    field :holdback_usdc, :string
    field :due_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec

    belongs_to :capsule, TechTree.BBH.Capsule,
      define_field: false,
      foreign_key: :capsule_id,
      references: :capsule_id,
      type: :string

    has_many :submissions, TechTree.BBH.ReviewSubmission,
      foreign_key: :request_id,
      references: :request_id

    timestamps()
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :request_id,
      :capsule_id,
      :review_kind,
      :visibility,
      :state,
      :claimed_by_wallet,
      :fee_quote_usdc,
      :holdback_usdc,
      :due_at,
      :closed_at
    ])
    |> validate_required([:request_id, :capsule_id, :review_kind, :visibility, :state])
  end
end

defmodule TechTree.BBH.ReviewSubmission do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:submission_id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "bbh_review_submissions" do
    field :request_id, :string
    field :capsule_id, :string
    field :reviewer_wallet, :string
    field :checklist_json, :map, default: %{}
    field :suggested_edits_json, :map, default: %{}
    field :decision, :string
    field :summary_md, :string
    field :genome_recommendation_source, :map, default: %{}
    field :certificate_payload, :map, default: %{}
    field :review_node_id, :string

    belongs_to :request, TechTree.BBH.ReviewRequest,
      define_field: false,
      foreign_key: :request_id,
      references: :request_id,
      type: :string

    belongs_to :capsule, TechTree.BBH.Capsule,
      define_field: false,
      foreign_key: :capsule_id,
      references: :capsule_id,
      type: :string

    timestamps()
  end

  def changeset(submission, attrs) do
    submission
    |> cast(attrs, [
      :submission_id,
      :request_id,
      :capsule_id,
      :reviewer_wallet,
      :checklist_json,
      :suggested_edits_json,
      :decision,
      :summary_md,
      :genome_recommendation_source,
      :certificate_payload,
      :review_node_id
    ])
    |> validate_required([
      :submission_id,
      :request_id,
      :capsule_id,
      :reviewer_wallet,
      :checklist_json,
      :suggested_edits_json,
      :decision,
      :summary_md
    ])
  end
end
