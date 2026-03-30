defmodule TechTree.Nodes.Node do
  @moduledoc false
  use TechTree.Schema

  alias TechTree.Types.{Ltree, Tsvector}

  @node_kinds [
    :hypothesis,
    :data,
    :result,
    :null_result,
    :review,
    :synthesis,
    :meta,
    :skill,
    :eval
  ]
  @node_statuses [:pinned, :anchored, :failed_anchor, :hidden, :deleted]
  @skill_slug_regex ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
  @skill_version_regex ~r/^[0-9]+\.[0-9]+\.[0-9]+$/

  @type kind ::
          :hypothesis
          | :data
          | :result
          | :null_result
          | :review
          | :synthesis
          | :meta
          | :skill
          | :eval

  @type t :: %__MODULE__{
          id: integer() | nil,
          path: String.t() | nil,
          depth: integer() | nil,
          seed: String.t() | nil,
          kind: kind() | nil,
          title: String.t() | nil,
          slug: String.t() | nil,
          summary: String.t() | nil,
          status: atom() | nil,
          publish_idempotency_key: String.t() | nil,
          manifest_cid: String.t() | nil,
          manifest_uri: String.t() | nil,
          manifest_hash: String.t() | nil,
          notebook_cid: String.t() | nil,
          notebook_source: String.t() | nil,
          skill_md_cid: String.t() | nil,
          skill_md_body: String.t() | nil,
          paid_payload: map() | nil,
          comments_locked: boolean(),
          parent_id: integer() | nil,
          creator_agent_id: integer() | nil
        }

  schema "nodes" do
    field(:path, Ltree)
    field(:depth, :integer, default: 0)

    field(:seed, :string)
    field(:kind, Ecto.Enum, values: @node_kinds)
    field(:title, :string)
    field(:slug, :string)
    field(:summary, :string)

    field(:status, Ecto.Enum, values: @node_statuses, default: :pinned)
    field(:publish_idempotency_key, :string)

    field(:manifest_cid, :string)
    field(:manifest_uri, :string)
    field(:manifest_hash, :string)
    field(:notebook_cid, :string)
    field(:notebook_source, :string)
    field(:skill_md_cid, :string)
    field(:skill_md_body, :string)

    field(:tx_hash, :string)
    field(:block_number, :integer)
    field(:chain_id, :integer)
    field(:contract_address, :string)

    field(:skill_slug, :string)
    field(:skill_version, :string)

    field(:child_count, :integer, default: 0)
    field(:comment_count, :integer, default: 0)
    field(:watcher_count, :integer, default: 0)
    field(:activity_score, :decimal, default: Decimal.new("0"))

    field(:comments_locked, :boolean, default: false)
    field(:search_document, Tsvector)
    field(:cross_chain_lineage, :map, virtual: true)
    field(:autoskill, :map, virtual: true)
    field(:paid_payload, :map, virtual: true)

    belongs_to(:parent, __MODULE__)
    belongs_to(:creator_agent, TechTree.Agents.AgentIdentity)

    has_many(:children, __MODULE__, foreign_key: :parent_id)
    has_many(:comments, TechTree.Comments.Comment)
    has_many(:tag_edges_out, TechTree.Nodes.NodeTagEdge, foreign_key: :src_node_id)
    has_many(:tag_edges_in, TechTree.Nodes.NodeTagEdge, foreign_key: :dst_node_id)
    has_many(:watchers, TechTree.Watches.NodeWatcher)
    has_many(:stars, TechTree.Stars.NodeStar)
    has_one(:chain_receipt, TechTree.Nodes.NodeChainReceipt)
    has_many(:cross_chain_links, TechTree.Nodes.NodeCrossChainLink)
    has_many(:lineage_claims, TechTree.Nodes.NodeLineageClaim, foreign_key: :subject_node_id)
    has_one(:node_bundle, TechTree.Autoskill.NodeBundle)
    has_one(:node_paid_payload, TechTree.NodeAccess.NodePaidPayload)
    has_many(:purchase_entitlements, TechTree.NodeAccess.NodePurchaseEntitlement)
    has_many(:autoskill_results, TechTree.Autoskill.Result, foreign_key: :skill_node_id)
    has_many(:autoskill_eval_results, TechTree.Autoskill.Result, foreign_key: :eval_node_id)
    has_many(:autoskill_reviews, TechTree.Autoskill.Review, foreign_key: :skill_node_id)
    has_one(:autoskill_listing, TechTree.Autoskill.Listing, foreign_key: :skill_node_id)

    timestamps()
  end

  @spec node_kinds() :: [kind()]
  def node_kinds, do: @node_kinds

  @spec creation_changeset(t(), TechTree.Agents.AgentIdentity.t(), map()) :: Ecto.Changeset.t()
  def creation_changeset(node, agent, attrs) do
    node
    |> cast(attrs, [
      :parent_id,
      :seed,
      :kind,
      :title,
      :slug,
      :summary,
      :skill_slug,
      :skill_version,
      :skill_md_body,
      :notebook_source
    ])
    |> put_change(:creator_agent_id, agent.id)
    |> put_change(:status, :pinned)
    |> validate_required([:seed, :kind, :title, :creator_agent_id, :parent_id, :notebook_source])
    |> validate_length(:seed, min: 1, max: 80)
    |> validate_length(:title, min: 1, max: 300)
    |> validate_length(:summary, max: 2_000)
    |> validate_notebook_source()
    |> validate_skill_fields()
    |> validate_non_skill_fields_empty()
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:creator_agent_id)
    |> check_constraint(:depth, name: :nodes_parent_depth_check)
    |> check_constraint(:parent_id, name: :nodes_non_seed_parent_required_check)
    |> check_constraint(:skill_slug, name: :nodes_skill_fields_check)
    |> check_constraint(:skill_version, name: :nodes_skill_fields_check)
    |> check_constraint(:skill_md_body, name: :nodes_skill_fields_check)
    |> unique_constraint([:skill_slug, :skill_version], name: :nodes_skill_unique_idx)
  end

  @spec materialized_artifact_changeset(t(), map()) :: Ecto.Changeset.t()
  def materialized_artifact_changeset(node, attrs) do
    node
    |> cast(attrs, [
      :manifest_cid,
      :manifest_uri,
      :manifest_hash,
      :notebook_cid,
      :skill_md_cid,
      :skill_md_body,
      :publish_idempotency_key,
      :status
    ])
    |> validate_required([
      :manifest_cid,
      :manifest_uri,
      :manifest_hash,
      :notebook_cid,
      :publish_idempotency_key,
      :status
    ])
    |> validate_materialized_skill_fields(node)
    |> check_constraint(:skill_md_body, name: :nodes_skill_fields_check)
  end

  @spec anchored_changeset(t(), map()) :: Ecto.Changeset.t()
  def anchored_changeset(node, attrs) do
    node
    |> cast(attrs, [:tx_hash, :block_number, :chain_id, :contract_address, :status])
    |> validate_required([:tx_hash, :chain_id, :contract_address, :status])
  end

  @spec hide_changeset(t()) :: Ecto.Changeset.t()
  def hide_changeset(node), do: change(node, status: :hidden)

  @spec validate_notebook_source(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_notebook_source(changeset) do
    case get_field(changeset, :notebook_source) do
      source when is_binary(source) ->
        if byte_size(String.trim(source)) > 0 do
          changeset
        else
          add_error(changeset, :notebook_source, "must be present")
        end

      _ ->
        add_error(changeset, :notebook_source, "must be present")
    end
  end

  @spec validate_skill_fields(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_skill_fields(changeset) do
    case get_field(changeset, :kind) do
      :skill ->
        changeset
        |> validate_required([:skill_slug, :skill_version, :skill_md_body])
        |> validate_format(:skill_slug, @skill_slug_regex)
        |> validate_format(:skill_version, @skill_version_regex)
        |> validate_change(:skill_md_body, fn :skill_md_body, value ->
          if is_binary(value) and byte_size(String.trim(value)) > 0 do
            []
          else
            [skill_md_body: "must be present"]
          end
        end)

      _ ->
        changeset
    end
  end

  @spec validate_non_skill_fields_empty(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_non_skill_fields_empty(changeset) do
    case get_field(changeset, :kind) do
      :skill ->
        changeset

      _ ->
        changeset
        |> validate_change(:skill_slug, &validate_non_skill_field_empty/2)
        |> validate_change(:skill_version, &validate_non_skill_field_empty/2)
        |> validate_change(:skill_md_body, &validate_non_skill_field_empty/2)
    end
  end

  @spec validate_materialized_skill_fields(Ecto.Changeset.t(), t()) :: Ecto.Changeset.t()
  defp validate_materialized_skill_fields(changeset, %__MODULE__{kind: :skill}) do
    changeset
    |> validate_required([:skill_md_body])
    |> validate_change(:skill_md_body, fn :skill_md_body, value ->
      if is_binary(value) and byte_size(String.trim(value)) > 0 do
        []
      else
        [skill_md_body: "must be present"]
      end
    end)
  end

  defp validate_materialized_skill_fields(changeset, _node) do
    validate_change(changeset, :skill_md_body, &validate_non_skill_field_empty/2)
  end

  @spec validate_non_skill_field_empty(atom(), term()) :: [{atom(), String.t()}]
  defp validate_non_skill_field_empty(field, value) do
    case value do
      nil ->
        []

      _ ->
        [{field, "must be nil unless kind is skill"}]
    end
  end
end
