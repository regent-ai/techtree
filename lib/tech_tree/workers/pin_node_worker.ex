defmodule TechTree.Workers.PinNodeWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :canonical,
    max_attempts: 5,
    unique: [period: 86_400, keys: [:node_id]]

  alias TechTree.Nodes

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: %{"node_id" => node_id}}) do
    case Nodes.pin_queued_node(node_id) do
      {:ok, _node} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
