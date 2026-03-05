defmodule TechTree.Workers.IndexCommentWorker do
  @moduledoc false
  use Oban.Worker, queue: :index, max_attempts: 20

  alias TechTree.Activity
  alias TechTree.Repo
  alias TechTree.Comments
  alias TechTree.Comments.Comment

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"comment_id" => comment_id}}) do
    comment = Repo.get!(Comment, comment_id)

    :ok = Comments.increment_node_comment_count!(comment.node_id)

    Activity.log!(
      "node.comment_created",
      :agent,
      comment.author_agent_id,
      comment.node_id,
      %{comment_id: comment.id}
    )

    :ok
  end
end
