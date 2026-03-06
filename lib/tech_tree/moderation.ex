defmodule TechTree.Moderation do
  @moduledoc false

  import TechTree.QueryHelpers

  alias TechTree.Repo
  alias TechTree.Moderation.ModerationAction
  alias TechTree.Nodes.Node
  alias TechTree.Comments.Comment
  alias TechTree.XMTPMirror.XmtpMessage
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Accounts.HumanUser

  @spec hide_node(integer() | String.t(), HumanUser.t(), String.t() | nil) :: :ok
  def hide_node(id, admin, reason) do
    node = Repo.get!(Node, normalize_id(id))
    node |> Node.hide_changeset() |> Repo.update!()

    log!(:node, node.id, "hide", admin, reason)
    :ok
  end

  @spec hide_comment(integer() | String.t(), HumanUser.t(), String.t() | nil) :: :ok
  def hide_comment(id, admin, reason) do
    comment = Repo.get!(Comment, normalize_id(id))
    comment |> Comment.hide_changeset() |> Repo.update!()

    log!(:comment, comment.id, "hide", admin, reason)
    :ok
  end

  @spec hide_trollbox_message(integer() | String.t(), HumanUser.t(), String.t() | nil) :: :ok
  def hide_trollbox_message(id, admin, reason) do
    message = Repo.get!(XmtpMessage, normalize_id(id))
    message |> Ecto.Changeset.change(moderation_state: "hidden") |> Repo.update!()

    log!(:trollbox_message, message.id, "hide", admin, reason)
    :ok
  end

  @spec ban_agent(integer() | String.t(), HumanUser.t(), String.t() | nil) :: :ok
  def ban_agent(id, admin, reason) do
    agent = Repo.get!(AgentIdentity, normalize_id(id))
    agent |> Ecto.Changeset.change(status: "banned") |> Repo.update!()

    log!(:agent, agent.id, "ban", admin, reason)
    :ok
  end

  @spec ban_human(integer() | String.t(), HumanUser.t(), String.t() | nil) :: :ok
  def ban_human(id, admin, reason) do
    human = Repo.get!(HumanUser, normalize_id(id))
    human |> Ecto.Changeset.change(role: "banned") |> Repo.update!()

    log!(:human, human.id, "ban", admin, reason)
    :ok
  end

  @spec log!(atom(), integer(), String.t(), HumanUser.t(), String.t() | nil) ::
          ModerationAction.t()
  defp log!(target_type, target_ref, action, admin, reason) do
    %ModerationAction{}
    |> ModerationAction.changeset(%{
      target_type: target_type,
      target_ref: target_ref,
      action: action,
      reason: reason,
      actor_type: :human,
      actor_ref: admin.id,
      payload: %{}
    })
    |> Repo.insert!()
  end

end
