defmodule TechTree.Workers.AnchorNodeWorker do
  @moduledoc false
  use Oban.Worker, queue: :chain, max_attempts: 20

  alias TechTree.Ethereum
  alias TechTree.Nodes
  alias TechTree.Repo
  alias TechTree.Nodes.Node
  alias TechTree.Workers.AwaitNodeReceiptWorker

  @await_unique_period 86_400

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
  defp do_perform(%Oban.Job{args: %{"node_id" => node_id} = args}) do
    node = Repo.get!(Node, node_id) |> Repo.preload(:creator_agent)

    case node.status do
      :anchored ->
        :ok

      :failed_anchor ->
        :ok

      :pinned ->
        manifest_uri = resolve_manifest_uri!(node)
        manifest_hash = resolve_manifest_hash!(node)
        idempotency_key = resolve_idempotency_key!(node, args)
        attempt =
          Nodes.touch_publish_attempt!(node.id, idempotency_key, manifest_uri, manifest_hash)

        with {:ok, tx_hash} <-
               resolve_tx_hash(node, attempt, idempotency_key, manifest_uri, manifest_hash) do
          :ok = Nodes.update_publish_attempt_status!(idempotency_key, "awaiting_receipt")

          {:ok, _job} =
            Oban.insert(
              AwaitNodeReceiptWorker.new(
                %{
                  "node_id" => node.id,
                  "tx_hash" => tx_hash,
                  "idempotency_key" => idempotency_key
                },
                unique: [period: @await_unique_period, keys: [:node_id]]
              )
            )

          :ok
        end

      status ->
        {:error,
         ArgumentError.exception("cannot anchor node #{node.id} while status is #{status}")}
    end
  end

  @spec resolve_tx_hash(Node.t(), map(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  defp resolve_tx_hash(%Node{} = node, attempt, idempotency_key, manifest_uri, manifest_hash) do
    cond do
      has_text?(attempt.tx_hash) ->
        {:ok, attempt.tx_hash}

      has_text?(node.tx_hash) ->
        Nodes.update_publish_attempt_status!(idempotency_key, "submitted", %{
          tx_hash: node.tx_hash
        })

        {:ok, node.tx_hash}

      true ->
        case Ethereum.create_node(%{
               node_id: node.id,
               parent_id: node.parent_id || 0,
               creator: node.creator_agent.wallet_address,
               manifest_uri: manifest_uri,
               manifest_hash: manifest_hash,
               kind: node_kind_to_uint8(node.kind)
             }) do
          {:ok, created_tx_hash} ->
            node
            |> Ecto.Changeset.change(tx_hash: created_tx_hash)
            |> Repo.update!()

            Nodes.update_publish_attempt_status!(idempotency_key, "submitted", %{
              tx_hash: created_tx_hash
            })

            {:ok, created_tx_hash}

          {:error, reason} ->
            {:error, {:create_node_failed, reason}}
        end
    end
  end

  @spec resolve_manifest_uri!(Node.t()) :: String.t()
  defp resolve_manifest_uri!(%Node{} = node) do
    if has_text?(node.manifest_uri) do
      node.manifest_uri
    else
      raise ArgumentError, "manifest_uri missing for node #{node.id}"
    end
  end

  @spec resolve_manifest_hash!(Node.t()) :: String.t()
  defp resolve_manifest_hash!(%Node{} = node) do
    if has_text?(node.manifest_hash) do
      node.manifest_hash
    else
      raise ArgumentError, "manifest_hash missing for node #{node.id}"
    end
  end

  @spec resolve_idempotency_key!(Node.t(), map()) :: String.t()
  defp resolve_idempotency_key!(%Node{} = node, args) do
    key = Map.get(args, "idempotency_key") || node.publish_idempotency_key

    if has_text?(key) do
      key
    else
      raise ArgumentError, "publish idempotency key missing for node #{node.id}"
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

    if has_text?(key) do
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

  @spec has_text?(String.t() | nil) :: boolean()
  defp has_text?(value) when is_binary(value), do: byte_size(String.trim(value)) > 0
  defp has_text?(_value), do: false
end
