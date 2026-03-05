defmodule TechTree.Workers.VerifyPinnedArtifactsWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, max_attempts: 10

  import Ecto.Query

  alias TechTree.Repo
  alias TechTree.Nodes.Node
  alias TechTree.Workers.{AnchorNodeWorker, PackageAndPinNodeWorker}

  @batch_size 200
  @unique_period 86_400

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{}) do
    pending_chain_nodes =
      Node
      |> where([n], n.status == :pending_chain)
      |> order_by([n], asc: n.inserted_at)
      |> limit(^@batch_size)
      |> Repo.all()

    Enum.reduce_while(pending_chain_nodes, :ok, fn node, _acc ->
      case enqueue_repair(node) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  rescue
    error -> {:error, error}
  end

  @spec enqueue_repair(Node.t()) :: :ok | {:error, term()}
  defp enqueue_repair(%Node{} = node) do
    cond do
      missing_or_mismatched_manifest?(node) ->
        insert_unique(PackageAndPinNodeWorker, %{"node_id" => node.id})

      has_tx_hash?(node.tx_hash) ->
        :ok

      true ->
        insert_unique(AnchorNodeWorker, %{
          "node_id" => node.id,
          "manifest_uri" => node.manifest_uri,
          "manifest_hash" => node.manifest_hash
        })
    end
  end

  @spec missing_or_mismatched_manifest?(Node.t()) :: boolean()
  defp missing_or_mismatched_manifest?(%Node{} = node) do
    expected_uri =
      case node.manifest_cid do
        cid when is_binary(cid) and byte_size(cid) > 0 -> "ipfs://#{cid}"
        _ -> nil
      end

    not has_text?(node.manifest_cid) or
      not has_text?(node.manifest_uri) or
      not has_text?(node.manifest_hash) or
      not has_text?(node.notebook_cid) or
      expected_uri != node.manifest_uri
  end

  @spec has_text?(String.t() | nil) :: boolean()
  defp has_text?(value) when is_binary(value), do: byte_size(value) > 0
  defp has_text?(_value), do: false

  @spec has_tx_hash?(String.t() | nil) :: boolean()
  defp has_tx_hash?(value) when is_binary(value), do: byte_size(value) > 0
  defp has_tx_hash?(_value), do: false

  @spec insert_unique(module(), map()) :: :ok | {:error, term()}
  defp insert_unique(worker, args) do
    case Oban.insert(worker.new(args, unique: [period: @unique_period, keys: [:node_id]])) do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
