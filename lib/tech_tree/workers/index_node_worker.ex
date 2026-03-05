defmodule TechTree.Workers.IndexNodeWorker do
  @moduledoc false
  use Oban.Worker, queue: :index, max_attempts: 20

  alias TechTree.Activity
  alias TechTree.Repo
  alias TechTree.Nodes
  alias TechTree.Nodes.Node

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"node_id" => node_id}}) do
    node = Repo.get!(Node, node_id)

    if node.parent_id do
      :ok = Nodes.increment_parent_child_count!(node.parent_id)

      Activity.log!(
        "node.child_created",
        :agent,
        node.creator_agent_id,
        node.parent_id,
        %{child_node_id: node.id}
      )
    end

    Activity.log!(
      "node.created",
      :agent,
      node.creator_agent_id,
      node.id,
      %{node_id: node.id, seed: node.seed, kind: node.kind}
    )

    :ok
  end
end
