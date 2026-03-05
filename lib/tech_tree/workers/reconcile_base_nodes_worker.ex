defmodule TechTree.Workers.ReconcileBaseNodesWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, max_attempts: 10

  import Ecto.Query

  alias TechTree.Repo
  alias TechTree.Nodes.Node
  alias TechTree.Workers.AwaitNodeReceiptWorker

  @batch_size 200
  @unique_period 86_400

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{}) do
    pending_receipts =
      Node
      |> where([n], n.status == :pending_chain)
      |> where([n], not is_nil(n.tx_hash) and n.tx_hash != "")
      |> where([n], not is_nil(n.manifest_uri) and n.manifest_uri != "")
      |> where([n], not is_nil(n.manifest_hash) and n.manifest_hash != "")
      |> order_by([n], asc: n.inserted_at)
      |> limit(^@batch_size)
      |> Repo.all()

    Enum.reduce_while(pending_receipts, :ok, fn node, _acc ->
      case enqueue_await_receipt(node) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  rescue
    error -> {:error, error}
  end

  @spec enqueue_await_receipt(Node.t()) :: :ok | {:error, term()}
  defp enqueue_await_receipt(%Node{} = node) do
    case Oban.insert(
           AwaitNodeReceiptWorker.new(
             %{
               "node_id" => node.id,
               "tx_hash" => node.tx_hash,
               "manifest_uri" => node.manifest_uri,
               "manifest_hash" => node.manifest_hash
             },
             unique: [period: @unique_period, keys: [:node_id]]
           )
         ) do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
