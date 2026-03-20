defmodule TechTree.Nodes do
  @moduledoc false

  alias Decimal, as: D
  alias TechTree.Nodes.{Metrics, Node, Publishing, Reads}

  @seed_roots ["ML", "Bioscience", "Polymarket", "DeFi", "Firmware", "Skills", "Evals"]

  @type node_create_error ::
          Ecto.Changeset.t()
          | :parent_required
          | :parent_not_found
          | :parent_not_anchored
          | :invalid_parent_id
          | term()
  @type transition_result :: :transitioned | :already_transitioned
  @type publish_attempt :: %{
          id: integer(),
          node_id: integer(),
          idempotency_key: String.t(),
          manifest_uri: String.t(),
          manifest_hash: String.t(),
          tx_hash: String.t() | nil,
          status: String.t(),
          attempt_count: integer(),
          last_error: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @spec seed_roots() :: [String.t()]
  def seed_roots, do: @seed_roots

  @spec list_public_seed_roots() :: [Node.t()]
  defdelegate list_public_seed_roots(), to: Reads

  @spec list_public_nodes(map()) :: [Node.t()]
  defdelegate list_public_nodes(params), to: Reads

  @spec get_public_node!(integer() | String.t()) :: Node.t()
  defdelegate get_public_node!(id), to: Reads

  @spec get_readable_node_for_agent!(integer(), integer() | String.t()) :: Node.t()
  defdelegate get_readable_node_for_agent!(agent_id, id), to: Reads

  @spec list_public_children(integer() | String.t(), map()) :: [Node.t()]
  defdelegate list_public_children(id, params), to: Reads

  @spec list_readable_children(integer(), integer() | String.t(), map()) :: [Node.t()]
  defdelegate list_readable_children(agent_id, id, params), to: Reads

  @spec list_tagged_edges(integer() | String.t()) :: [TechTree.Nodes.NodeTagEdge.t()]
  defdelegate list_tagged_edges(id), to: Reads

  @spec list_hot_nodes(String.t(), map()) :: [Node.t()]
  defdelegate list_hot_nodes(seed, params), to: Reads

  @spec list_public_nodes_by_ids([integer() | String.t()]) :: [Node.t()]
  defdelegate list_public_nodes_by_ids(ids), to: Reads

  @spec get_skill_by_slug_and_version(String.t(), String.t()) :: Node.t() | nil
  defdelegate get_skill_by_slug_and_version(slug, version), to: Reads

  @spec get_skill_by_slug_and_version!(String.t(), String.t()) :: Node.t()
  def get_skill_by_slug_and_version!(slug, version) do
    get_skill_by_slug_and_version(slug, version) || raise Ecto.NoResultsError, queryable: Node
  end

  @spec get_latest_skill(String.t()) :: Node.t() | nil
  defdelegate get_latest_skill(slug), to: Reads

  @spec get_latest_skill!(String.t()) :: Node.t()
  def get_latest_skill!(slug) do
    get_latest_skill(slug) || raise Ecto.NoResultsError, queryable: Node
  end

  @spec create_agent_node(TechTree.Agents.AgentIdentity.t(), map(), keyword()) ::
          {:ok, Node.t()} | {:error, node_create_error()}
  defdelegate create_agent_node(agent, attrs, opts \\ []), to: Publishing

  @spec create_seed_root!(String.t(), String.t()) :: Node.t()
  defdelegate create_seed_root!(seed_name, title), to: Publishing

  @spec get_agent_node_by_idempotency(integer(), String.t() | nil) :: Node.t() | nil
  defdelegate get_agent_node_by_idempotency(agent_id, idempotency_key), to: Publishing

  @spec mark_node_anchored!(integer() | String.t(), map()) :: transition_result()
  defdelegate mark_node_anchored!(node_id, attrs), to: Publishing

  @spec mark_node_failed_anchor!(integer() | String.t()) :: transition_result()
  defdelegate mark_node_failed_anchor!(node_id), to: Publishing

  @spec touch_publish_attempt!(integer(), String.t(), String.t(), String.t()) :: publish_attempt()
  defdelegate touch_publish_attempt!(node_id, idempotency_key, manifest_uri, manifest_hash),
    to: Publishing

  @spec get_publish_attempt(String.t()) :: publish_attempt() | nil
  defdelegate get_publish_attempt(idempotency_key), to: Publishing

  @spec update_publish_attempt_status!(String.t(), String.t(), map()) :: :ok
  defdelegate update_publish_attempt_status!(idempotency_key, status, extra_fields \\ %{}),
    to: Publishing

  @spec refresh_hot_scores!() :: :ok
  defdelegate refresh_hot_scores!(), to: Metrics

  @spec refresh_parent_child_metrics!(integer() | String.t() | nil) :: :ok
  defdelegate refresh_parent_child_metrics!(parent_id), to: Metrics

  @spec refresh_comment_metrics!(integer() | String.t()) :: :ok
  defdelegate refresh_comment_metrics!(node_id), to: Metrics

  @spec refresh_watcher_metrics!(integer() | String.t()) :: :ok
  defdelegate refresh_watcher_metrics!(node_id), to: Metrics

  @spec refresh_activity_score!(Node.t() | integer() | String.t()) :: D.t() | nil
  defdelegate refresh_activity_score!(node_or_id), to: Metrics

  @spec calculate_activity_score(Node.t()) :: D.t()
  defdelegate calculate_activity_score(node), to: Metrics
end
