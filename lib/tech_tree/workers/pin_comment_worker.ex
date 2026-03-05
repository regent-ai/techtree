defmodule TechTree.Workers.PinCommentWorker do
  @moduledoc false
  use Oban.Worker, queue: :canonical, max_attempts: 20

  alias TechTree.IPFS.CommentObjectBuilder
  alias TechTree.Comments
  alias TechTree.Repo
  alias TechTree.Comments.Comment
  alias TechTree.Workers.{IndexCommentWorker, BroadcastCommentWorker}

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: %{"comment_id" => comment_id}}) do
    comment = Repo.get!(Comment, comment_id)
    object = CommentObjectBuilder.build_and_pin!(comment)

    :ok = Comments.mark_comment_ready!(comment.id, %{body_cid: object.cid})

    {:ok, _} = Oban.insert(IndexCommentWorker.new(%{"comment_id" => comment.id}))
    {:ok, _} = Oban.insert(BroadcastCommentWorker.new(%{"comment_id" => comment.id}))

    :ok
  rescue
    error -> {:error, error}
  end
end
