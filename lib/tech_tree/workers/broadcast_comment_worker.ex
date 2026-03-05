defmodule TechTree.Workers.BroadcastCommentWorker do
  @moduledoc false
  use Oban.Worker, queue: :realtime, max_attempts: 10

  alias TechTree.Repo
  alias TechTree.Comments.Comment
  alias Phoenix.PubSub

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"comment_id" => comment_id}}) do
    comment = Repo.get!(Comment, comment_id)

    payload = %{
      event: "comment_ready",
      comment_id: comment.id,
      node_id: comment.node_id
    }

    PubSub.broadcast(TechTree.PubSub, "node:#{comment.node_id}", payload)
    PubSub.broadcast(TechTree.PubSub, "activity:global", payload)

    :ok
  end
end
