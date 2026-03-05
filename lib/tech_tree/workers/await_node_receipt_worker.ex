defmodule TechTree.Workers.AwaitNodeReceiptWorker do
  @moduledoc false
  use Oban.Worker, queue: :chain, max_attempts: 100

  alias TechTree.Base
  alias TechTree.Repo
  alias TechTree.Nodes
  alias TechTree.Nodes.Node

  alias TechTree.Workers.{
    IndexNodeWorker,
    UpdateMetricsWorker,
    BroadcastNodeReadyWorker,
    FanoutWatcherNotificationsWorker
  }

  @downstream_unique_period 86_400

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{
        args: %{
          "node_id" => node_id,
          "tx_hash" => tx_hash,
          "manifest_uri" => manifest_uri,
          "manifest_hash" => manifest_hash
        }
      }) do
    node = Repo.get!(Node, node_id) |> Repo.preload(:creator_agent)
    :ok = verify_anchor_payload!(node, manifest_uri, manifest_hash)
    verification = build_verification_input!(node)

    case Base.fetch_receipt(tx_hash, verification) do
      {:ok, receipt} ->
        transition_result =
          Nodes.mark_node_ready!(node_id, %{
            tx_hash: tx_hash,
            block_number: receipt.block_number,
            chain_id: receipt.chain_id,
            contract_address: receipt.contract_address,
            log_index: receipt.log_index
          })

        case transition_result do
          :transitioned ->
            enqueue_post_ready_jobs(node_id)
            :ok

          :already_transitioned ->
            :ok
        end

        :ok

      :not_found ->
        raise "receipt not ready"

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec enqueue_post_ready_jobs(integer() | String.t()) :: :ok
  defp enqueue_post_ready_jobs(node_id) do
    {:ok, _job} =
      Oban.insert(
        IndexNodeWorker.new(%{"node_id" => node_id},
          unique: [period: @downstream_unique_period, keys: [:node_id]]
        )
      )

    {:ok, _job} =
      Oban.insert(
        UpdateMetricsWorker.new(%{"node_id" => node_id},
          unique: [period: @downstream_unique_period, keys: [:node_id]]
        )
      )

    {:ok, _job} =
      Oban.insert(
        BroadcastNodeReadyWorker.new(%{"node_id" => node_id},
          unique: [period: @downstream_unique_period, keys: [:node_id]]
        )
      )

    {:ok, _job} =
      Oban.insert(
        FanoutWatcherNotificationsWorker.new(
          %{"node_id" => node_id},
          unique: [period: @downstream_unique_period, keys: [:node_id]]
        )
      )

    :ok
  end

  @spec verify_anchor_payload!(Node.t(), String.t(), String.t()) :: :ok
  defp verify_anchor_payload!(%Node{} = node, manifest_uri, manifest_hash) do
    if node.manifest_uri != manifest_uri do
      raise ArgumentError, "manifest_uri mismatch while awaiting receipt for node #{node.id}"
    end

    if node.manifest_hash != manifest_hash do
      raise ArgumentError, "manifest_hash mismatch while awaiting receipt for node #{node.id}"
    end

    :ok
  end

  @spec build_verification_input!(Node.t()) :: map()
  defp build_verification_input!(%Node{} = node) do
    creator = node.creator_agent && node.creator_agent.wallet_address

    if not (is_binary(creator) and byte_size(String.trim(creator)) > 0) do
      raise ArgumentError, "creator wallet missing while awaiting receipt for node #{node.id}"
    end

    %{
      node_id: node.id,
      parent_id: node.parent_id || 0,
      creator: creator,
      manifest_hash: node.manifest_hash,
      kind: node_kind_to_uint8(node.kind)
    }
  end

  @spec node_kind_to_uint8(atom()) :: 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7
  defp node_kind_to_uint8(:hypothesis), do: 0
  defp node_kind_to_uint8(:data), do: 1
  defp node_kind_to_uint8(:result), do: 2
  defp node_kind_to_uint8(:null_result), do: 3
  defp node_kind_to_uint8(:review), do: 4
  defp node_kind_to_uint8(:synthesis), do: 5
  defp node_kind_to_uint8(:meta), do: 6
  defp node_kind_to_uint8(:skill), do: 7
end
