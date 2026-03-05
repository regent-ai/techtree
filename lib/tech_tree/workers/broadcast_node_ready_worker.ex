defmodule TechTree.Workers.BroadcastNodeReadyWorker do
  @moduledoc false
  use Oban.Worker, queue: :realtime, max_attempts: 10

  alias TechTree.Repo
  alias TechTree.Nodes.Node
  alias Phoenix.PubSub

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"node_id" => node_id}}) do
    node = Repo.get!(Node, node_id)

    payload = %{
      event: "node_ready",
      node_id: node.id,
      parent_id: node.parent_id,
      seed: node.seed,
      activity_score: node.activity_score
    }

    PubSub.broadcast(TechTree.PubSub, "activity:global", payload)
    PubSub.broadcast(TechTree.PubSub, "seed:#{node.seed}", payload)

    if node.parent_id do
      PubSub.broadcast(TechTree.PubSub, "node:#{node.parent_id}", payload)
    end

    :ok
  end
end
