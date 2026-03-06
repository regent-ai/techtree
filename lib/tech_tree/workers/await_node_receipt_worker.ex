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
  def perform(%Oban.Job{} = job) do
    case do_perform(job) do
      :ok ->
        :ok

      {:error, reason} ->
        maybe_mark_failed_anchor(job, reason)
        {:error, reason}
    end
  rescue
    error ->
      maybe_mark_failed_anchor(job, error)
      {:error, error}
  end

  @spec do_perform(Oban.Job.t()) :: :ok | {:error, term()}
  defp do_perform(%Oban.Job{
         args:
           %{
             "node_id" => node_id,
             "tx_hash" => tx_hash
           } = args
       }) do
    node = Repo.get!(Node, node_id) |> Repo.preload(:creator_agent)

    case node.status do
      :anchored ->
        :ok

      :failed_anchor ->
        :ok

      :pinned ->
        verification = build_verification_input!(node)
        idempotency_key = resolve_idempotency_key!(node, args)

        case Base.fetch_receipt(tx_hash, verification) do
          {:ok, receipt} ->
            transition_result =
              Nodes.mark_node_anchored!(node_id, %{
                tx_hash: tx_hash,
                block_number: receipt.block_number,
                chain_id: receipt.chain_id,
                contract_address: receipt.contract_address,
                log_index: receipt.log_index
              })

            case transition_result do
              :transitioned ->
                enqueue_post_ready_jobs(node_id)
                Nodes.update_publish_attempt_status!(idempotency_key, "anchored", %{
                  tx_hash: tx_hash
                })
                :ok

              :already_transitioned ->
                Nodes.update_publish_attempt_status!(idempotency_key, "anchored", %{
                  tx_hash: tx_hash
                })
                :ok
            end

          :not_found ->
            {:error, :receipt_not_ready}

          {:error, reason} ->
            {:error, reason}
        end

      status ->
        {:error,
         ArgumentError.exception(
           "cannot await receipt for node #{node.id} while status is #{status}"
         )}
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

  @spec resolve_idempotency_key!(Node.t(), map()) :: String.t()
  defp resolve_idempotency_key!(%Node{} = node, args) do
    key = Map.get(args, "idempotency_key") || node.publish_idempotency_key

    if is_binary(key) and byte_size(String.trim(key)) > 0 do
      key
    else
      raise ArgumentError,
            "publish idempotency key missing while awaiting receipt for node #{node.id}"
    end
  end

  @spec maybe_mark_failed_anchor(Oban.Job.t(), term()) :: :ok
  defp maybe_mark_failed_anchor(
         %Oban.Job{attempt: attempt, max_attempts: max_attempts, args: args},
         reason
       )
       when attempt >= max_attempts do
    case mark_node_failed_anchor(Map.get(args, "node_id")) do
      :transitioned -> _ = maybe_mark_publish_attempt_failed(args, reason)
      :already_transitioned -> :ok
      :skipped -> :ok
    end

    :ok
  rescue
    _ -> :ok
  end

  defp maybe_mark_failed_anchor(%Oban.Job{}, _reason), do: :ok

  @spec mark_node_failed_anchor(integer() | String.t() | nil) ::
          Nodes.transition_result() | :skipped
  defp mark_node_failed_anchor(node_id) do
    case normalize_node_id(node_id) do
      nil -> :skipped
      normalized_id -> Nodes.mark_node_failed_anchor!(normalized_id)
    end
  end

  @spec maybe_mark_publish_attempt_failed(map(), term()) :: :ok
  defp maybe_mark_publish_attempt_failed(args, reason) do
    key = Map.get(args, "idempotency_key")

    if is_binary(key) and byte_size(String.trim(key)) > 0 do
      Nodes.update_publish_attempt_status!(key, "failed_anchor", %{last_error: reason})
    end

    :ok
  end

  @spec normalize_node_id(integer() | String.t() | nil) :: integer() | nil
  defp normalize_node_id(value) when is_integer(value), do: value

  defp normalize_node_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp normalize_node_id(_value), do: nil

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
