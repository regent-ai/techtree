defmodule TechTree.Nodes do
  @moduledoc false

  import Ecto.Query
  require Logger

  alias Ecto.Multi
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Repo
  alias TechTree.Nodes.{Node, NodeTagEdge, NodeChainReceipt}
  alias TechTree.Workers.PackageAndPinNodeWorker

  @seed_roots ["ML", "Bioscience", "Polymarket", "DeFi", "Firmware", "Skills", "Evals"]
  @transition_telemetry_event [:tech_tree, :nodes, :transition]

  @type node_create_error :: Ecto.Changeset.t() | :parent_required | :parent_not_found | term()
  @type transition_result :: :transitioned | :already_transitioned

  @spec seed_roots() :: [String.t()]
  def seed_roots, do: @seed_roots

  @spec list_public_nodes(map()) :: [Node.t()]
  def list_public_nodes(params) do
    limit = parse_limit(params, 50)

    public_nodes_query()
    |> order_by([n, _creator], desc: n.activity_score, desc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec get_public_node!(integer() | String.t()) :: Node.t()
  def get_public_node!(id) do
    normalized_id = normalize_id(id)

    tag_edges_query =
      NodeTagEdge
      |> where([e], e.dst_node_id in subquery(public_node_ids_query()))
      |> order_by([e], asc: e.ordinal)

    public_nodes_query()
    |> where([n, _creator], n.id == ^normalized_id)
    |> limit(1)
    |> Repo.one!()
    |> Repo.preload([:creator_agent, tag_edges_out: tag_edges_query])
  end

  @spec list_public_children(integer() | String.t(), map()) :: [Node.t()]
  def list_public_children(id, params) do
    parent_id = normalize_id(id)
    limit = parse_limit(params, 100)

    public_nodes_query()
    |> where([n, _creator], n.parent_id == ^parent_id)
    |> where([n, _creator], n.parent_id in subquery(public_node_ids_query()))
    |> order_by([n, _creator], desc: n.activity_score, asc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec list_tagged_edges(integer() | String.t()) :: [NodeTagEdge.t()]
  def list_tagged_edges(id) do
    node_id = normalize_id(id)

    NodeTagEdge
    |> where([e], e.src_node_id == ^node_id)
    |> where([e], e.src_node_id in subquery(public_node_ids_query()))
    |> where([e], e.dst_node_id in subquery(public_node_ids_query()))
    |> order_by([e], asc: e.ordinal)
    |> Repo.all()
  end

  @spec list_hot_nodes(String.t(), map()) :: [Node.t()]
  def list_hot_nodes(seed, params) do
    limit = parse_limit(params, 25)

    public_nodes_query()
    |> where([n, _creator], n.seed == ^seed)
    |> order_by([n, _creator], desc: n.activity_score, desc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec get_skill_by_slug_and_version!(String.t(), String.t()) :: Node.t()
  def get_skill_by_slug_and_version!(slug, version) do
    public_nodes_query()
    |> where(
      [n, _creator],
      n.kind == :skill and n.skill_slug == ^slug and n.skill_version == ^version
    )
    |> order_by([n, _creator], desc: n.inserted_at)
    |> limit(1)
    |> Repo.one!()
  end

  @spec get_latest_skill!(String.t()) :: Node.t()
  def get_latest_skill!(slug) do
    public_nodes_query()
    |> where([n, _creator], n.kind == :skill and n.skill_slug == ^slug)
    |> order_by([n, _creator], desc: n.inserted_at)
    |> limit(1)
    |> Repo.one!()
  end

  @spec create_agent_node(TechTree.Agents.AgentIdentity.t(), map()) ::
          {:ok, Node.t()} | {:error, node_create_error()}
  def create_agent_node(agent, attrs) do
    normalized_attrs = normalize_create_attrs(attrs)

    Multi.new()
    |> Multi.run(:parent, fn _repo, _changes -> fetch_parent(normalized_attrs) end)
    |> Multi.insert(:node, fn %{parent: parent} ->
      %Node{}
      |> Node.creation_changeset(agent, normalized_attrs)
      # Satisfy DB parent/depth integrity constraint on initial insert.
      |> Ecto.Changeset.put_change(:depth, parent.depth + 1)
    end)
    |> Multi.run(:path, fn repo, %{node: node, parent: parent} ->
      {path, depth} = build_path(parent, node.id)
      node |> Ecto.Changeset.change(path: path, depth: depth) |> repo.update()
    end)
    |> Multi.run(:sidelinks, fn repo, %{path: node} ->
      insert_sidelinks(repo, node.id, normalized_attrs["sidelinks"] || [])
    end)
    |> Multi.run(:oban, fn _repo, %{path: node} ->
      Oban.insert(PackageAndPinNodeWorker.new(%{"node_id" => node.id}))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{path: node}} -> {:ok, node}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @spec create_seed_root!(String.t(), String.t()) :: Node.t()
  def create_seed_root!(seed_name, title) do
    existing =
      Node
      |> where([n], n.seed == ^seed_name and is_nil(n.parent_id))
      |> limit(1)
      |> Repo.one()

    if existing do
      existing
    else
      %Node{}
      |> Ecto.Changeset.change(%{
        seed: seed_name,
        kind: :hypothesis,
        title: title,
        status: :ready,
        creator_agent_id: system_agent_id(),
        notebook_source: "# seed root",
        path: "pending",
        depth: 0
      })
      |> Repo.insert!()
      |> then(fn node ->
        node
        |> Ecto.Changeset.change(path: "n#{node.id}", depth: 0)
        |> Repo.update!()
      end)
    end
  end

  @spec mark_node_pending_chain!(integer() | String.t(), map()) :: transition_result()
  def mark_node_pending_chain!(node_id, attrs) do
    normalized_id = normalize_id(node_id)

    Repo.transaction(fn ->
      normalized_id
      |> fetch_node_for_update!()
      |> transition_node_to_pending_chain!(normalized_id, attrs)
    end)
    |> unwrap_transition_transaction!()
  end

  @spec mark_node_ready!(integer() | String.t(), map()) :: transition_result()
  def mark_node_ready!(node_id, attrs) do
    normalized_id = normalize_id(node_id)

    Repo.transaction(fn ->
      normalized_id
      |> fetch_node_for_update!()
      |> transition_node_to_ready!(normalized_id, attrs)
    end)
    |> unwrap_transition_transaction!()
  end

  @spec transition_node_to_pending_chain!(Node.t(), integer(), map()) ::
          transition_result()
  defp transition_node_to_pending_chain!(
         %Node{status: :ready},
         node_id,
         _attrs
       ) do
    emit_transition_event(node_id, :ready, :pending_chain, :already_transitioned, %{
      reason: "already_ready"
    })

    :already_transitioned
  end

  defp transition_node_to_pending_chain!(
         %Node{status: :pending_chain} = node,
         node_id,
         attrs
       ) do
    incoming_payload = materialized_payload_from_attrs(attrs)

    cond do
      materialized_payload_matches?(node, incoming_payload) ->
        emit_transition_event(node_id, :pending_chain, :pending_chain, :already_transitioned, %{
          reason: "identical_materialized_payload"
        })

        :already_transitioned

      has_text?(node.tx_hash) ->
        emit_transition_event(node_id, :pending_chain, :pending_chain, :rejected, %{
          reason: "tx_hash_already_assigned"
        })

        raise ArgumentError,
              "cannot update materialized payload for node #{node_id} after tx hash assignment"

      true ->
        node
        |> Node.materialized_artifact_changeset(Map.put(attrs, :status, :pending_chain))
        |> Repo.update!()

        emit_transition_event(node_id, :pending_chain, :pending_chain, :transitioned, %{
          reason: "materialized_payload_updated"
        })

        :transitioned
    end
  end

  defp transition_node_to_pending_chain!(
         %Node{status: status} = node,
         node_id,
         attrs
       )
       when status == :pending_ipfs do
    node
    |> Node.materialized_artifact_changeset(Map.put(attrs, :status, :pending_chain))
    |> Repo.update!()

    emit_transition_event(node_id, :pending_ipfs, :pending_chain, :transitioned, %{
      reason: "materialized_payload_created"
    })

    :transitioned
  end

  defp transition_node_to_pending_chain!(%Node{status: status}, node_id, _attrs) do
    emit_transition_event(node_id, status, :pending_chain, :rejected, %{reason: "invalid_status"})

    raise ArgumentError,
          "cannot transition node #{node_id} from #{status} to pending_chain"
  end

  @spec transition_node_to_ready!(Node.t(), integer(), map()) :: transition_result()
  defp transition_node_to_ready!(%Node{status: :ready} = node, node_id, attrs) do
    tx_hash = attr_value(attrs, :tx_hash)

    if node.tx_hash == tx_hash do
      ensure_chain_receipt!(node_id, attrs)
      emit_transition_event(node_id, :ready, :ready, :already_transitioned, %{
        reason: "matching_tx_hash"
      })
      :already_transitioned
    else
      emit_transition_event(node_id, :ready, :ready, :rejected, %{reason: "mismatched_tx_hash"})

      raise ArgumentError,
            "cannot mark node #{node_id} ready with mismatched tx hash"
    end
  end

  defp transition_node_to_ready!(%Node{status: :pending_chain} = node, node_id, attrs) do
    ensure_materialized_payload!(node, node_id)
    incoming_tx_hash = attr_value(attrs, :tx_hash)

    if is_binary(node.tx_hash) and byte_size(node.tx_hash) > 0 and
         node.tx_hash != incoming_tx_hash do
      emit_transition_event(node_id, :pending_chain, :ready, :rejected, %{
        reason: "mismatched_pending_tx_hash"
      })

      raise ArgumentError,
            "cannot mark node #{node_id} ready with mismatched pending tx hash"
    end

    node
    |> Node.ready_changeset(Map.put(attrs, :status, :ready))
    |> Repo.update!()

    ensure_chain_receipt!(node_id, attrs)

    emit_transition_event(node_id, :pending_chain, :ready, :transitioned, %{
      reason: "receipt_recorded"
    })

    :transitioned
  end

  defp transition_node_to_ready!(%Node{status: status}, node_id, _attrs) do
    emit_transition_event(node_id, status, :ready, :rejected, %{reason: "invalid_status"})

    raise ArgumentError,
          "cannot transition node #{node_id} from #{status} to ready"
  end

  @spec update_search_document!(integer() | String.t()) :: :ok
  def update_search_document!(_node_id), do: :ok

  @spec increment_parent_child_count!(integer() | String.t()) :: :ok
  def increment_parent_child_count!(parent_id) do
    Node
    |> where([n], n.id == ^normalize_id(parent_id))
    |> Repo.update_all(inc: [child_count: 1])

    :ok
  end

  @spec refresh_hot_scores!() :: :ok
  def refresh_hot_scores! do
    Node
    |> where([n], n.status == :ready)
    |> update([n],
      set: [
        activity_score:
          fragment("? * 10 + ? * 3 + ?", n.child_count, n.comment_count, n.watcher_count)
      ]
    )
    |> Repo.update_all([])

    :ok
  end

  @spec fetch_parent(map()) :: {:ok, Node.t()} | {:error, :parent_required | :parent_not_found}
  defp fetch_parent(%{"parent_id" => nil}), do: {:error, :parent_required}

  defp fetch_parent(%{"parent_id" => parent_id}) do
    case Repo.get(Node, parent_id) do
      nil -> {:error, :parent_not_found}
      parent -> {:ok, parent}
    end
  end

  @spec insert_sidelinks(Ecto.Repo.t(), integer(), [map()]) ::
          {:ok, :ok} | {:error, Ecto.Changeset.t()}
  defp insert_sidelinks(repo, src_node_id, sidelinks) do
    result =
      sidelinks
      |> Enum.take(4)
      |> Enum.with_index(1)
      |> Enum.reduce_while(:ok, fn {entry, default_ordinal}, _acc ->
        attrs = %{
          src_node_id: src_node_id,
          dst_node_id: normalize_id(Map.get(entry, "node_id") || Map.get(entry, :node_id)),
          tag: Map.get(entry, "tag") || Map.get(entry, :tag) || "related",
          ordinal: Map.get(entry, "ordinal") || Map.get(entry, :ordinal) || default_ordinal
        }

        case %NodeTagEdge{} |> NodeTagEdge.changeset(attrs) |> repo.insert() do
          {:ok, _edge} -> {:cont, :ok}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      end)

    case result do
      :ok -> {:ok, :ok}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec normalize_create_attrs(map()) :: map()
  defp normalize_create_attrs(attrs) do
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.update("parent_id", nil, &normalize_optional_id/1)
  end

  @spec normalize_optional_id(integer() | String.t() | nil) :: integer() | nil
  defp normalize_optional_id(nil), do: nil
  defp normalize_optional_id(value), do: normalize_id(value)

  @spec normalize_id(integer() | String.t()) :: integer()
  defp normalize_id(value) when is_integer(value), do: value
  defp normalize_id(value) when is_binary(value), do: String.to_integer(value)

  @spec fetch_node_for_update!(integer()) :: Node.t()
  defp fetch_node_for_update!(node_id) do
    Node
    |> where([n], n.id == ^node_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  @spec materialized_payload_from_attrs(map()) :: map()
  defp materialized_payload_from_attrs(attrs) do
    %{
      manifest_cid: attr_value(attrs, :manifest_cid),
      manifest_uri: attr_value(attrs, :manifest_uri),
      manifest_hash: attr_value(attrs, :manifest_hash),
      notebook_cid: attr_value(attrs, :notebook_cid),
      skill_md_cid: attr_value(attrs, :skill_md_cid),
      skill_md_body: attr_value(attrs, :skill_md_body)
    }
  end

  @spec materialized_payload_matches?(Node.t(), map()) :: boolean()
  defp materialized_payload_matches?(%Node{} = node, incoming_payload) do
    Enum.all?(incoming_payload, fn {field, value} ->
      normalize_optional_text(Map.get(node, field)) == normalize_optional_text(value)
    end)
  end

  @spec normalize_optional_text(term()) :: String.t() | nil
  defp normalize_optional_text(value) when is_binary(value), do: String.trim(value)
  defp normalize_optional_text(nil), do: nil
  defp normalize_optional_text(value), do: value

  @spec build_path(Node.t() | nil, integer()) :: {String.t(), non_neg_integer()}
  defp build_path(nil, id), do: {"n#{id}", 0}
  defp build_path(parent, id), do: {"#{parent.path}.n#{id}", parent.depth + 1}

  @spec system_agent_id() :: integer()
  defp system_agent_id do
    :tech_tree
    |> Application.get_env(:system_agent_id, "1")
    |> case do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end

  @spec parse_limit(map(), pos_integer()) :: pos_integer()
  defp parse_limit(params, fallback) do
    case Map.get(params, "limit") do
      nil -> fallback
      value when is_integer(value) and value > 0 -> min(value, 200)
      value when is_binary(value) -> value |> String.to_integer() |> min(200)
      _ -> fallback
    end
  rescue
    _ -> fallback
  end

  @spec ensure_chain_receipt!(integer(), map()) :: :ok
  defp ensure_chain_receipt!(node_id, attrs) do
    case Repo.get_by(NodeChainReceipt, node_id: node_id) do
      nil ->
        %NodeChainReceipt{}
        |> NodeChainReceipt.changeset(%{
          node_id: node_id,
          chain_id: attr_value(attrs, :chain_id),
          contract_address: attr_value(attrs, :contract_address),
          tx_hash: attr_value(attrs, :tx_hash),
          block_number: attr_value(attrs, :block_number),
          log_index: attr_value(attrs, :log_index) || 0,
          confirmed_at: DateTime.utc_now()
        })
        |> Repo.insert!()

      receipt ->
        verify_receipt_match!(receipt, attrs)
    end

    :ok
  end

  @spec verify_receipt_match!(NodeChainReceipt.t(), map()) :: :ok
  defp verify_receipt_match!(receipt, attrs) do
    incoming = %{
      tx_hash: attr_value(attrs, :tx_hash),
      chain_id: attr_value(attrs, :chain_id),
      contract_address: attr_value(attrs, :contract_address),
      block_number: attr_value(attrs, :block_number),
      log_index: attr_value(attrs, :log_index)
    }

    mismatch =
      Enum.find(incoming, fn {field, value} ->
        not is_nil(value) and Map.get(receipt, field) != value
      end)

    case mismatch do
      nil ->
        :ok

      {field, value} ->
        raise ArgumentError,
              "node chain receipt mismatch on #{field}: existing=#{inspect(Map.get(receipt, field))} incoming=#{inspect(value)}"
    end
  end

  @spec ensure_materialized_payload!(Node.t(), integer()) :: :ok
  defp ensure_materialized_payload!(node, node_id) do
    required_fields = [:manifest_cid, :manifest_uri, :manifest_hash, :notebook_cid]

    case Enum.find(required_fields, fn field -> not has_text?(Map.get(node, field)) end) do
      nil ->
        :ok

      missing_field ->
        emit_transition_event(node_id, :pending_chain, :ready, :rejected, %{
          reason: "missing_materialized_payload",
          missing_field: missing_field
        })

        raise ArgumentError,
              "cannot mark node #{node_id} ready without #{missing_field} in pending_chain"
    end
  end

  @spec has_text?(term()) :: boolean()
  defp has_text?(value) when is_binary(value), do: byte_size(String.trim(value)) > 0
  defp has_text?(_value), do: false

  @spec unwrap_transition_transaction!({:ok, transition_result()} | {:error, term()}) ::
          transition_result()
  defp unwrap_transition_transaction!({:ok, result}), do: result

  defp unwrap_transition_transaction!({:error, reason}) do
    Logger.warning("node transition transaction failed: #{inspect(reason)}")
    raise RuntimeError, "node transition transaction failed: #{inspect(reason)}"
  end

  @spec emit_transition_event(integer(), atom(), atom(), atom(), map()) :: :ok
  defp emit_transition_event(node_id, from_status, to_status, outcome, metadata) do
    metadata =
      metadata
      |> Map.put(:node_id, node_id)
      |> Map.put(:from_status, to_string(from_status))
      |> Map.put(:to_status, to_string(to_status))
      |> Map.put(:outcome, to_string(outcome))

    :telemetry.execute(@transition_telemetry_event, %{count: 1}, metadata)

    Logger.debug(
      "node transition node_id=#{node_id} from=#{from_status} to=#{to_status} outcome=#{outcome} metadata=#{inspect(metadata)}"
    )

    :ok
  end

  @spec attr_value(map(), atom()) :: term()
  defp attr_value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  @spec public_nodes_query() :: Ecto.Query.t()
  defp public_nodes_query do
    Node
    |> join(:inner, [n], creator in AgentIdentity, on: creator.id == n.creator_agent_id)
    |> where([n, creator], n.status == :ready and creator.status == "active")
  end

  @spec public_node_ids_query() :: Ecto.Query.t()
  defp public_node_ids_query do
    public_nodes_query()
    |> select([n, _creator], n.id)
  end
end
