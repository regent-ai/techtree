defmodule TechTree.Nodes.Publishing do
  @moduledoc false

  import Ecto.Query
  require Logger

  alias Ecto.Multi
  alias TechTree.Agents
  alias TechTree.IPFS.NodeBundleBuilder
  alias TechTree.Nodes.{Lineage, Node, NodeChainReceipt, NodeTagEdge}
  alias TechTree.Nodes.Reads
  alias TechTree.Repo
  alias TechTree.Workers.AnchorNodeWorker

  @transition_telemetry_event [:tech_tree, :nodes, :transition]

  @spec create_agent_node(TechTree.Agents.AgentIdentity.t(), map(), keyword()) ::
          {:ok, Node.t()} | {:error, term()}
  def create_agent_node(agent, attrs, opts \\ []) do
    publish_start = System.monotonic_time()
    normalized_attrs = normalize_create_attrs(attrs)
    requested_publish_idempotency_key = attr_value(normalized_attrs, :publish_idempotency_key)
    skip_idempotency_lookup? = Keyword.get(opts, :skip_idempotency_lookup, false)

    result =
      if skip_idempotency_lookup? do
        create_fresh_agent_node(
          agent,
          normalized_attrs,
          requested_publish_idempotency_key ||
            build_requested_publish_idempotency_key(agent.id, normalized_attrs)
        )
      else
        case find_existing_node_by_idempotency(agent.id, requested_publish_idempotency_key) do
          %Node{} = existing ->
            {:ok, existing}

          nil ->
            create_fresh_agent_node(
              agent,
              normalized_attrs,
              requested_publish_idempotency_key ||
                build_requested_publish_idempotency_key(agent.id, normalized_attrs)
            )
        end
      end

    emit_publish_stop(publish_start, result)
    result
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
        status: :anchored,
        publish_idempotency_key: "seed:#{seed_name}",
        creator_agent_id: ensure_system_agent!().id,
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

  @spec get_agent_node_by_idempotency(integer(), String.t() | nil) :: Node.t() | nil
  def get_agent_node_by_idempotency(_agent_id, nil), do: nil

  def get_agent_node_by_idempotency(agent_id, idempotency_key)
      when is_integer(agent_id) and is_binary(idempotency_key) do
    find_existing_node_by_idempotency(agent_id, normalize_optional_text(idempotency_key))
  end

  @spec mark_node_anchored!(integer() | String.t(), map()) ::
          :transitioned | :already_transitioned
  def mark_node_anchored!(node_id, attrs) do
    normalized_id = Reads.normalize_id(node_id)

    Repo.transaction(fn ->
      normalized_id
      |> fetch_node_for_update!()
      |> transition_node_to_anchored!(normalized_id, attrs)
    end)
    |> unwrap_transition_transaction!()
  end

  @spec mark_node_failed_anchor!(integer() | String.t()) :: :transitioned | :already_transitioned
  def mark_node_failed_anchor!(node_id) do
    normalized_id = Reads.normalize_id(node_id)

    Repo.transaction(fn ->
      normalized_id
      |> fetch_node_for_update!()
      |> transition_node_to_failed_anchor!(normalized_id)
    end)
    |> unwrap_transition_transaction!()
  end

  @spec touch_publish_attempt!(integer(), String.t(), String.t(), String.t()) :: map()
  def touch_publish_attempt!(node_id, idempotency_key, manifest_uri, manifest_hash) do
    upsert_publish_attempt_with_repo!(
      Repo,
      node_id,
      idempotency_key,
      manifest_uri,
      manifest_hash,
      "pinned"
    )
  end

  @spec get_publish_attempt(String.t()) :: map() | nil
  def get_publish_attempt(idempotency_key) when is_binary(idempotency_key) do
    "node_publish_attempts"
    |> where([attempt], attempt.idempotency_key == ^idempotency_key)
    |> select([attempt], %{
      id: attempt.id,
      node_id: attempt.node_id,
      idempotency_key: attempt.idempotency_key,
      manifest_uri: attempt.manifest_uri,
      manifest_hash: attempt.manifest_hash,
      tx_hash: attempt.tx_hash,
      status: attempt.status,
      attempt_count: attempt.attempt_count,
      last_error: attempt.last_error,
      inserted_at: attempt.inserted_at,
      updated_at: attempt.updated_at
    })
    |> Repo.one()
  end

  @spec update_publish_attempt_status!(String.t(), String.t(), map()) :: :ok
  def update_publish_attempt_status!(idempotency_key, status, extra_fields \\ %{})
      when is_binary(idempotency_key) and is_binary(status) and is_map(extra_fields) do
    now = DateTime.utc_now()

    {set_fields, inc_fields} =
      extra_fields
      |> Map.put(:status, status)
      |> Map.put(:updated_at, now)
      |> normalize_publish_attempt_update_fields(status)

    updates = [set: Keyword.new(set_fields)]

    updates =
      case inc_fields do
        [] -> updates
        _ -> Keyword.put(updates, :inc, inc_fields)
      end

    "node_publish_attempts"
    |> where([attempt], attempt.idempotency_key == ^idempotency_key)
    |> Repo.update_all(updates)

    :ok
  end

  defp create_fresh_agent_node(agent, normalized_attrs, requested_publish_idempotency_key) do
    with {:ok, parent} <- fetch_parent(normalized_attrs),
         {:ok, staged_node} <-
           build_staged_node(
             agent,
             parent,
             normalized_attrs,
             requested_publish_idempotency_key
           ),
         {:ok, bundle} <-
           build_bundle_for_node(
             staged_node,
             Map.put(normalized_attrs, "parent_cid", parent.manifest_cid)
           ),
         {:ok, node} <-
           persist_published_node(
             agent.id,
             staged_node,
             normalized_attrs,
             bundle,
             requested_publish_idempotency_key
           ) do
      {:ok, node}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_parent(%{"parent_id" => nil}), do: {:error, :parent_required}

  defp fetch_parent(%{"parent_id" => parent_id}) do
    case Repo.get(Node, parent_id) do
      nil ->
        {:error, :parent_not_found}

      %Node{status: :anchored} = parent ->
        {:ok, parent}

      %Node{} ->
        {:error, :parent_not_anchored}
    end
  rescue
    ArgumentError -> {:error, :invalid_parent_id}
  end

  defp insert_sidelinks(repo, src_node_id, sidelinks) do
    result =
      sidelinks
      |> Enum.take(4)
      |> Enum.with_index(1)
      |> Enum.reduce_while(:ok, fn {entry, default_ordinal}, _acc ->
        attrs = %{
          src_node_id: src_node_id,
          dst_node_id: Reads.normalize_id(Map.get(entry, "node_id") || Map.get(entry, :node_id)),
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

  defp normalize_create_attrs(attrs) do
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.update("parent_id", nil, &normalize_optional_id/1)
    |> normalize_publish_idempotency_key_attr()
  end

  defp normalize_publish_idempotency_key_attr(attrs) do
    key =
      attrs
      |> Map.get("idempotency_key", Map.get(attrs, "publish_idempotency_key"))
      |> normalize_optional_text()

    case key do
      nil -> Map.delete(attrs, "publish_idempotency_key")
      normalized -> Map.put(attrs, "publish_idempotency_key", normalized)
    end
  end

  defp normalize_optional_id(nil), do: nil
  defp normalize_optional_id(value), do: Reads.normalize_id(value)

  defp find_existing_node_by_idempotency(_agent_id, nil), do: nil

  defp find_existing_node_by_idempotency(agent_id, idempotency_key) do
    Node
    |> where(
      [n],
      n.creator_agent_id == ^agent_id and n.publish_idempotency_key == ^idempotency_key
    )
    |> order_by([n], desc: n.id)
    |> limit(1)
    |> Repo.one()
  end

  defp fetch_node_for_update!(node_id) do
    Node
    |> where([n], n.id == ^node_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp transition_node_to_anchored!(%Node{status: :anchored} = node, node_id, attrs) do
    tx_hash = attr_value(attrs, :tx_hash)

    if node.tx_hash == tx_hash do
      ensure_chain_receipt!(node_id, attrs)
      emit_anchor_stop(node_id, node, :already_transitioned)

      emit_transition_event(node_id, :anchored, :anchored, :already_transitioned, %{
        reason: "matching_tx_hash"
      })

      :already_transitioned
    else
      emit_transition_event(node_id, :anchored, :anchored, :rejected, %{
        reason: "mismatched_tx_hash"
      })

      raise ArgumentError,
            "cannot mark node #{node_id} anchored with mismatched tx hash"
    end
  end

  defp transition_node_to_anchored!(%Node{status: :pinned} = node, node_id, attrs) do
    ensure_materialized_payload!(node, node_id)
    incoming_tx_hash = attr_value(attrs, :tx_hash)

    if is_binary(node.tx_hash) and byte_size(node.tx_hash) > 0 and
         node.tx_hash != incoming_tx_hash do
      emit_transition_event(node_id, :pinned, :anchored, :rejected, %{
        reason: "mismatched_pending_tx_hash"
      })

      raise ArgumentError,
            "cannot mark node #{node_id} anchored with mismatched pending tx hash"
    end

    node
    |> Node.anchored_changeset(Map.put(attrs, :status, :anchored))
    |> Repo.update!()

    ensure_chain_receipt!(node_id, attrs)
    emit_anchor_stop(node_id, node, :transitioned)

    emit_transition_event(node_id, :pinned, :anchored, :transitioned, %{
      reason: "receipt_recorded"
    })

    :transitioned
  end

  defp transition_node_to_anchored!(%Node{status: status}, node_id, _attrs) do
    emit_transition_event(node_id, status, :anchored, :rejected, %{reason: "invalid_status"})

    raise ArgumentError,
          "cannot transition node #{node_id} from #{status} to anchored"
  end

  defp transition_node_to_failed_anchor!(%Node{status: :failed_anchor}, node_id) do
    emit_transition_event(node_id, :failed_anchor, :failed_anchor, :already_transitioned, %{
      reason: "already_failed_anchor"
    })

    :already_transitioned
  end

  defp transition_node_to_failed_anchor!(%Node{status: :pinned} = node, node_id) do
    node
    |> Ecto.Changeset.change(status: :failed_anchor)
    |> Repo.update!()

    emit_transition_event(node_id, :pinned, :failed_anchor, :transitioned, %{
      reason: "anchor_attempt_exhausted"
    })

    emit_failed_anchor_event(node_id)

    :transitioned
  end

  defp transition_node_to_failed_anchor!(%Node{status: :anchored}, node_id) do
    emit_transition_event(node_id, :anchored, :failed_anchor, :already_transitioned, %{
      reason: "already_anchored"
    })

    :already_transitioned
  end

  defp transition_node_to_failed_anchor!(%Node{status: status}, node_id) do
    emit_transition_event(node_id, status, :failed_anchor, :rejected, %{reason: "invalid_status"})

    raise ArgumentError,
          "cannot transition node #{node_id} from #{status} to failed_anchor"
  end

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_text(nil), do: nil
  defp normalize_optional_text(value), do: value

  defp normalize_publish_attempt_update_fields(extra_fields, status) do
    inc_fields =
      case status do
        "submitted" -> [attempt_count: 1]
        "failed_anchor" -> [attempt_count: 1]
        _ -> []
      end

    set_fields =
      extra_fields
      |> Map.update(:last_error, default_last_error(status), &normalize_last_error(status, &1))
      |> Enum.to_list()

    {set_fields, inc_fields}
  end

  defp default_last_error("failed_anchor"), do: nil
  defp default_last_error(_status), do: nil

  defp normalize_last_error("failed_anchor", value), do: inspect(value)
  defp normalize_last_error(_status, value), do: value

  defp build_path(nil, id), do: {"n#{id}", 0}
  defp build_path(parent, id), do: {"#{parent.path}.n#{id}", parent.depth + 1}

  defp build_and_pin_bundle(node, payload), do: NodeBundleBuilder.build_and_pin!(node, payload)

  defp build_bundle_for_node(node, normalized_attrs) do
    {:ok, build_and_pin_bundle(node, build_bundle_payload(normalized_attrs))}
  rescue
    error -> {:error, error}
  end

  defp build_bundle_payload(normalized_attrs) do
    %{
      "notebook_source" => normalized_attrs["notebook_source"],
      "skill_md_body" => normalized_attrs["skill_md_body"]
    }
  end

  defp build_staged_node(agent, parent, normalized_attrs, requested_publish_idempotency_key) do
    with {:ok, node_id} <- reserve_node_id() do
      {path, depth} = build_path(parent, node_id)

      changeset =
        %Node{}
        |> Node.creation_changeset(agent, normalized_attrs)
        |> Ecto.Changeset.put_change(:id, node_id)
        |> Ecto.Changeset.put_change(:path, path)
        |> Ecto.Changeset.put_change(:depth, depth)
        |> Ecto.Changeset.put_change(:publish_idempotency_key, requested_publish_idempotency_key)

      case changeset.valid? do
        true -> {:ok, Ecto.Changeset.apply_changes(changeset)}
        false -> {:error, changeset}
      end
    end
  end

  defp reserve_node_id do
    case Ecto.Adapters.SQL.query(
           Repo,
           "SELECT nextval(pg_get_serial_sequence('nodes', 'id'))",
           []
         ) do
      {:ok, %{rows: [[node_id]]}} when is_integer(node_id) ->
        {:ok, node_id}

      {:ok, %{rows: rows}} ->
        {:error, {:unexpected_node_id_result, rows}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_published_node(
         agent_id,
         staged_node,
         normalized_attrs,
         bundle,
         requested_publish_idempotency_key
       ) do
    publish_idempotency_key =
      normalize_publish_idempotency_key(
        staged_node.id,
        bundle.manifest_hash_hex,
        normalized_attrs,
        requested_publish_idempotency_key
      )

    Multi.new()
    |> Multi.insert(:node, fn _changes ->
      staged_node
      |> Node.materialized_artifact_changeset(%{
        manifest_cid: bundle.manifest_cid,
        manifest_uri: bundle.manifest_uri,
        manifest_hash: bundle.manifest_hash_hex,
        notebook_cid: bundle.notebook_cid,
        skill_md_cid: bundle.skill_md_cid,
        skill_md_body: bundle.skill_md_body,
        publish_idempotency_key: publish_idempotency_key,
        status: :pinned
      })
      |> Ecto.Changeset.unique_constraint(:publish_idempotency_key,
        name: :nodes_publish_idempotency_key_uidx
      )
    end)
    |> Multi.run(:sidelinks, fn repo, %{node: node} ->
      insert_sidelinks(repo, node.id, normalized_attrs["sidelinks"] || [])
    end)
    |> Multi.run(:cross_chain_link, fn repo, %{node: node} ->
      Lineage.create_initial_author_link(
        repo,
        node,
        Agents.get_agent!(agent_id),
        normalized_attrs["cross_chain_link"]
      )
    end)
    |> Multi.run(:publish_attempt, fn repo, %{node: node} ->
      {:ok,
       upsert_publish_attempt_with_repo!(
         repo,
         node.id,
         node.publish_idempotency_key,
         node.manifest_uri,
         node.manifest_hash,
         "pinned"
       )}
    end)
    |> Multi.run(:oban, fn _repo, %{node: node} -> enqueue_anchor_job(node) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{node: node}} ->
        {:ok, node}

      {:error, :node, %Ecto.Changeset{} = changeset, _changes} ->
        maybe_resolve_idempotent_insert_conflict(agent_id, publish_idempotency_key, changeset)

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp enqueue_anchor_job(node) do
    Oban.insert(
      AnchorNodeWorker.new(
        %{
          "node_id" => node.id,
          "idempotency_key" => node.publish_idempotency_key
        },
        unique: [period: 86_400, keys: [:node_id]]
      )
    )
  end

  defp maybe_resolve_idempotent_insert_conflict(agent_id, publish_idempotency_key, changeset) do
    if publish_idempotency_conflict?(changeset) do
      case find_existing_node_by_idempotency(agent_id, publish_idempotency_key) do
        %Node{} = node -> {:ok, node}
        nil -> {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  defp publish_idempotency_conflict?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:publish_idempotency_key, {_message, opts}} ->
        opts[:constraint] == :unique

      _ ->
        false
    end)
  end

  defp build_publish_idempotency_key(node_id, manifest_hash),
    do: "node:#{node_id}:#{manifest_hash}"

  defp build_requested_publish_idempotency_key(agent_id, attrs) do
    attr_value(attrs, :publish_idempotency_key) ||
      "node:req:#{agent_id}:#{System.unique_integer([:positive, :monotonic])}"
  end

  defp normalize_publish_idempotency_key(node_id, manifest_hash, attrs, existing) do
    attr_value(attrs, :publish_idempotency_key) ||
      existing ||
      build_publish_idempotency_key(node_id, manifest_hash || "missing-manifest-hash")
  end

  defp upsert_publish_attempt_with_repo!(
         repo,
         node_id,
         idempotency_key,
         manifest_uri,
         manifest_hash,
         status
       ) do
    now = DateTime.utc_now()

    repo.insert_all(
      "node_publish_attempts",
      [
        %{
          node_id: node_id,
          idempotency_key: idempotency_key,
          manifest_uri: manifest_uri,
          manifest_hash: manifest_hash,
          tx_hash: nil,
          status: status,
          attempt_count: 0,
          last_error: nil,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: [
        set: [
          node_id: node_id,
          manifest_uri: manifest_uri,
          manifest_hash: manifest_hash,
          status: status,
          updated_at: now,
          last_error: nil
        ]
      ],
      conflict_target: [:idempotency_key]
    )

    "node_publish_attempts"
    |> where([attempt], attempt.idempotency_key == ^idempotency_key)
    |> select([attempt], %{
      id: attempt.id,
      node_id: attempt.node_id,
      idempotency_key: attempt.idempotency_key,
      manifest_uri: attempt.manifest_uri,
      manifest_hash: attempt.manifest_hash,
      tx_hash: attempt.tx_hash,
      status: attempt.status,
      attempt_count: attempt.attempt_count,
      last_error: attempt.last_error,
      inserted_at: attempt.inserted_at,
      updated_at: attempt.updated_at
    })
    |> repo.one!()
  end

  defp system_agent_id do
    :tech_tree
    |> Application.get_env(:system_agent_id, "1")
    |> case do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end

  defp ensure_system_agent! do
    system_id = system_agent_id()

    Repo.get_by(TechTree.Agents.AgentIdentity, id: system_id) ||
      Agents.upsert_verified_agent!(%{
        chain_id: configured_registry_chain_id(),
        registry_address: "0x0000000000000000000000000000000000000001",
        token_id: system_id,
        wallet_address: "0x" <> String.pad_leading(Integer.to_string(system_id, 16), 40, "0"),
        label: "system-agent-#{system_id}",
        status: "active"
      })
  end

  defp configured_registry_chain_id do
    :tech_tree
    |> Application.get_env(:ethereum, [])
    |> Keyword.get(:chain_id, 84_532)
    |> case do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end

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

  defp ensure_materialized_payload!(node, node_id) do
    required_fields = [
      :manifest_cid,
      :manifest_uri,
      :manifest_hash,
      :notebook_cid,
      :publish_idempotency_key
    ]

    case Enum.find(required_fields, fn field -> not has_text?(Map.get(node, field)) end) do
      nil ->
        :ok

      missing_field ->
        emit_transition_event(node_id, :pinned, :anchored, :rejected, %{
          reason: "missing_materialized_payload",
          missing_field: missing_field
        })

        raise ArgumentError,
              "cannot mark node #{node_id} anchored without #{missing_field} in pinned"
    end
  end

  defp has_text?(value) when is_binary(value), do: byte_size(String.trim(value)) > 0
  defp has_text?(_value), do: false

  defp unwrap_transition_transaction!({:ok, result}), do: result

  defp unwrap_transition_transaction!({:error, reason}) do
    Logger.warning("node transition transaction failed: #{inspect(reason)}")
    raise RuntimeError, "node transition transaction failed: #{inspect(reason)}"
  end

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

  defp emit_publish_stop(start_time_native, result) do
    duration = System.monotonic_time() - start_time_native

    outcome =
      case result do
        {:ok, _node} -> "ok"
        {:error, _reason} -> "error"
      end

    :telemetry.execute([:tech_tree, :nodes, :publish, :stop], %{duration: duration}, %{
      outcome: outcome
    })

    :ok
  end

  defp emit_anchor_stop(node_id, node, outcome) do
    :telemetry.execute(
      [:tech_tree, :nodes, :anchor, :stop],
      %{duration: anchor_latency_native(node)},
      %{node_id: node_id, outcome: Atom.to_string(outcome)}
    )

    :ok
  end

  defp anchor_latency_native(%Node{inserted_at: nil}), do: 0

  defp anchor_latency_native(%Node{inserted_at: inserted_at}) do
    inserted_at
    |> DateTime.diff(DateTime.utc_now(), :millisecond)
    |> Kernel.abs()
    |> System.convert_time_unit(:millisecond, :native)
  end

  defp emit_failed_anchor_event(node_id) do
    :telemetry.execute([:tech_tree, :nodes, :failed_anchor], %{count: 1}, %{node_id: node_id})
    :ok
  end

  defp attr_value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
end
