defmodule TechTree.Chatbox.Reactions do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Accounts.HumanUser
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Chatbox.Actor
  alias TechTree.Chatbox.Message
  alias TechTree.Chatbox.MessageReaction
  alias TechTree.Chatbox.Messages
  alias TechTree.Chatbox.Payload
  alias TechTree.Repo

  @type actor :: HumanUser.t() | AgentIdentity.t()

  @spec react_to_message(actor(), integer() | String.t(), map()) ::
          {:ok, Message.t()}
          | {:error,
             :human_banned
             | :agent_banned
             | :xmtp_identity_required
             | :message_not_found
             | :invalid_reaction_emoji
             | :invalid_reaction_operation
             | Ecto.Changeset.t()}
  def react_to_message(actor, message_id, attrs) when is_map(attrs) do
    with :ok <- Actor.ensure_can_react(actor),
         {:ok, normalized_message_id} <- Payload.parse_message_id(message_id, :message_not_found),
         {:ok, emoji} <- Payload.normalize_reaction_emoji(attrs),
         {:ok, operation} <- Payload.normalize_reaction_operation(attrs),
         {:ok, message} <- Messages.fetch_public_message(normalized_message_id) do
      update_message_reactions(message, Actor.actor_identity(actor), emoji, operation)
    end
  end

  defp update_message_reactions(
         %Message{id: message_id},
         {actor_type, actor_ref},
         emoji,
         operation
       ) do
    Repo.transaction(fn ->
      message =
        Message
        |> where([m], m.id == ^message_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()
        |> Repo.preload([:author_human, :author_agent])

      with :ok <- apply_reaction_operation(message_id, actor_type, actor_ref, emoji, operation),
           updated_reactions <- reaction_counts_for_message(message_id),
           {:ok, updated} <-
             message
             |> Ecto.Changeset.change(reactions: updated_reactions)
             |> Repo.update() do
        Repo.preload(updated, [:author_human, :author_agent])
      else
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, %Message{} = updated} -> {:ok, updated}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp apply_reaction_operation(message_id, actor_type, actor_ref, emoji, :add) do
    %MessageReaction{}
    |> MessageReaction.changeset(%{
      message_id: message_id,
      actor_kind: actor_type,
      actor_ref: actor_ref,
      reaction: emoji
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:message_id, :actor_kind, :actor_ref, :reaction]
    )
    |> case do
      {:ok, _reaction} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp apply_reaction_operation(message_id, actor_type, actor_ref, emoji, :remove) do
    MessageReaction
    |> where(
      [reaction],
      reaction.message_id == ^message_id and reaction.actor_kind == ^actor_type and
        reaction.actor_ref == ^actor_ref and reaction.reaction == ^emoji
    )
    |> Repo.delete_all()

    :ok
  end

  defp reaction_counts_for_message(message_id) do
    MessageReaction
    |> where([reaction], reaction.message_id == ^message_id)
    |> group_by([reaction], reaction.reaction)
    |> select([reaction], {reaction.reaction, count(reaction.id)})
    |> Repo.all()
    |> Map.new()
  end
end
