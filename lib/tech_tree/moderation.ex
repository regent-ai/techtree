defmodule TechTree.Moderation do
  @moduledoc false

  import Ecto.Query
  import TechTree.QueryHelpers

  alias TechTree.Repo
  alias TechTree.Nodes
  alias TechTree.Moderation.ModerationAction
  alias TechTree.Nodes.Node
  alias TechTree.Comments.Comment
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Accounts.HumanUser
  alias TechTree.Chatbox
  alias TechTree.Chatbox.Message
  alias TechTree.XMTPMirror

  @default_dashboard_limit 60
  @default_history_limit 12
  @default_actions_limit 16

  @type dashboard_state :: %{
          messages: [Message.t()],
          selected_message_id: integer() | nil,
          selected_message: Message.t() | nil,
          actor_history: [Message.t()],
          recent_actions: [ModerationAction.t()]
        }

  @type safe_action_result ::
          :ok
          | {:error, :message_not_found}
          | {:error, :agent_not_found}
          | {:error, :human_not_found}

  @type chatbox_membership_action_result ::
          {:ok, XMTPMirror.room_admin_action_status()}
          | {:error, :human_not_found}
          | {:error, :human_banned}
          | {:error, :room_not_found}
          | {:error, :xmtp_identity_required}

  @spec hide_node(integer() | String.t(), HumanUser.t(), String.t() | nil) :: :ok
  def hide_node(id, admin, reason) do
    node = Repo.get!(Node, normalize_id(id))
    node |> Node.hide_changeset() |> Repo.update!()
    :ok = Nodes.refresh_parent_child_metrics!(node.parent_id)
    _ = Nodes.refresh_activity_score!(node.id)

    log!(:node, node.id, "hide", admin, reason)
    :ok
  end

  @spec hide_comment(integer() | String.t(), HumanUser.t(), String.t() | nil) :: :ok
  def hide_comment(id, admin, reason) do
    comment = Repo.get!(Comment, normalize_id(id))
    comment |> Comment.hide_changeset() |> Repo.update!()
    :ok = Nodes.refresh_comment_metrics!(comment.node_id)

    log!(:comment, comment.id, "hide", admin, reason)
    :ok
  end

  @spec hide_chatbox_message(integer() | String.t(), HumanUser.t(), String.t() | nil) :: :ok
  def hide_chatbox_message(id, admin, reason) do
    {:ok, message} = Chatbox.hide_message(id)

    log!(:chatbox_message, message.id, "hide", admin, reason)
    :ok
  end

  @spec unhide_chatbox_message(integer() | String.t(), HumanUser.t(), String.t() | nil) :: :ok
  def unhide_chatbox_message(id, admin, reason) do
    {:ok, message} = Chatbox.unhide_message(id)

    log!(:chatbox_message, message.id, "unhide", admin, reason)
    :ok
  end

  @spec ban_agent(integer() | String.t(), HumanUser.t(), String.t() | nil) :: :ok
  def ban_agent(id, admin, reason) do
    agent = Repo.get!(AgentIdentity, normalize_id(id))
    agent |> Ecto.Changeset.change(status: "banned") |> Repo.update!()
    :ok = reconcile_agent_metrics!(agent.id)

    log!(:agent, agent.id, "ban", admin, reason)
    :ok
  end

  @spec unban_agent(integer() | String.t(), HumanUser.t(), String.t() | nil) :: :ok
  def unban_agent(id, admin, reason) do
    agent = Repo.get!(AgentIdentity, normalize_id(id))
    agent |> Ecto.Changeset.change(status: "active") |> Repo.update!()
    :ok = reconcile_agent_metrics!(agent.id)

    log!(:agent, agent.id, "unban", admin, reason)
    :ok
  end

  @spec ban_human(integer() | String.t(), HumanUser.t(), String.t() | nil) :: :ok
  def ban_human(id, admin, reason) do
    human = Repo.get!(HumanUser, normalize_id(id))
    human |> Ecto.Changeset.change(role: "banned") |> Repo.update!()
    :ok = XMTPMirror.best_effort_remove_human_from_canonical_room(human.id)

    log!(:human, human.id, "ban", admin, reason)
    :ok
  end

  @spec unban_human(integer() | String.t(), HumanUser.t(), String.t() | nil) :: :ok
  def unban_human(id, admin, reason) do
    human = Repo.get!(HumanUser, normalize_id(id))
    human |> Ecto.Changeset.change(role: "user") |> Repo.update!()

    log!(:human, human.id, "unban", admin, reason)
    :ok
  end

  @spec hide_chatbox_message_if_present(integer() | String.t(), HumanUser.t(), String.t() | nil) ::
          safe_action_result()
  def hide_chatbox_message_if_present(id, admin, reason) do
    with {:ok, message} <- Chatbox.hide_message_if_present(id) do
      log!(:chatbox_message, message.id, "hide", admin, reason)
      :ok
    end
  end

  @spec unhide_chatbox_message_if_present(
          integer() | String.t(),
          HumanUser.t(),
          String.t() | nil
        ) :: safe_action_result()
  def unhide_chatbox_message_if_present(id, admin, reason) do
    with {:ok, message} <- Chatbox.unhide_message_if_present(id) do
      log!(:chatbox_message, message.id, "unhide", admin, reason)
      :ok
    end
  end

  @spec ban_agent_if_present(integer() | String.t(), HumanUser.t(), String.t() | nil) ::
          safe_action_result()
  def ban_agent_if_present(id, admin, reason) do
    with {:ok, agent} <- fetch_entity(AgentIdentity, id, :agent_not_found) do
      agent |> Ecto.Changeset.change(status: "banned") |> Repo.update!()
      :ok = reconcile_agent_metrics!(agent.id)

      log!(:agent, agent.id, "ban", admin, reason)
      :ok
    end
  end

  @spec unban_agent_if_present(integer() | String.t(), HumanUser.t(), String.t() | nil) ::
          safe_action_result()
  def unban_agent_if_present(id, admin, reason) do
    with {:ok, agent} <- fetch_entity(AgentIdentity, id, :agent_not_found) do
      agent |> Ecto.Changeset.change(status: "active") |> Repo.update!()
      :ok = reconcile_agent_metrics!(agent.id)

      log!(:agent, agent.id, "unban", admin, reason)
      :ok
    end
  end

  @spec ban_human_if_present(integer() | String.t(), HumanUser.t(), String.t() | nil) ::
          safe_action_result()
  def ban_human_if_present(id, admin, reason) do
    with {:ok, human} <- fetch_entity(HumanUser, id, :human_not_found) do
      human |> Ecto.Changeset.change(role: "banned") |> Repo.update!()
      :ok = XMTPMirror.best_effort_remove_human_from_canonical_room(human.id)

      log!(:human, human.id, "ban", admin, reason)
      :ok
    end
  end

  @spec unban_human_if_present(integer() | String.t(), HumanUser.t(), String.t() | nil) ::
          safe_action_result()
  def unban_human_if_present(id, admin, reason) do
    with {:ok, human} <- fetch_entity(HumanUser, id, :human_not_found) do
      human |> Ecto.Changeset.change(role: "user") |> Repo.update!()

      log!(:human, human.id, "unban", admin, reason)
      :ok
    end
  end

  @spec add_human_to_chatbox(integer() | String.t(), HumanUser.t(), String.t() | nil) ::
          chatbox_membership_action_result()
  def add_human_to_chatbox(id, admin, reason) do
    human = Repo.get!(HumanUser, normalize_id(id))

    case XMTPMirror.add_human_to_canonical_room(human.id) do
      {:ok, :enqueued} ->
        log!(:human, human.id, "add_chatbox_member", admin, reason)
        {:ok, :enqueued}

      {:ok, status} ->
        {:ok, status}

      {:error, reason_code} ->
        {:error, reason_code}
    end
  end

  @spec remove_human_from_chatbox(integer() | String.t(), HumanUser.t(), String.t() | nil) ::
          chatbox_membership_action_result()
  def remove_human_from_chatbox(id, admin, reason) do
    human = Repo.get!(HumanUser, normalize_id(id))

    case XMTPMirror.remove_human_from_canonical_room(human.id) do
      {:ok, :enqueued} ->
        log!(:human, human.id, "remove_chatbox_member", admin, reason)
        {:ok, :enqueued}

      {:ok, status} ->
        {:ok, status}

      {:error, reason_code} ->
        {:error, reason_code}
    end
  end

  @spec list_chatbox_dashboard_messages(map()) :: [Message.t()]
  def list_chatbox_dashboard_messages(filters \\ %{}) when is_map(filters) do
    limit =
      filters
      |> Map.get("limit", Map.get(filters, :limit, @default_dashboard_limit))
      |> normalize_limit()

    Message
    |> join(:left, [message], human in assoc(message, :author_human))
    |> join(:left, [message, _human], agent in assoc(message, :author_agent))
    |> maybe_filter_dashboard_query(filters)
    |> order_by([message], desc: message.inserted_at, desc: message.id)
    |> limit(^limit)
    |> preload([_message, human, agent], author_human: human, author_agent: agent)
    |> Repo.all()
  end

  @spec list_recent_actions(keyword()) :: [ModerationAction.t()]
  def list_recent_actions(opts \\ []) do
    limit = opts |> Keyword.get(:limit, 40) |> normalize_limit()

    ModerationAction
    |> order_by([action], desc: action.inserted_at, desc: action.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec list_chatbox_author_history(:human | :agent, integer(), keyword()) :: [Message.t()]
  def list_chatbox_author_history(author_kind, author_ref, opts \\ [])
      when author_kind in [:human, :agent] and is_integer(author_ref) and author_ref > 0 do
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()

    Message
    |> join(:left, [message], human in assoc(message, :author_human))
    |> join(:left, [message, _human], agent in assoc(message, :author_agent))
    |> where([message], message.author_kind == ^author_kind)
    |> where_author_ref(author_kind, author_ref)
    |> order_by([message], desc: message.inserted_at, desc: message.id)
    |> limit(^limit)
    |> preload([_message, human, agent], author_human: human, author_agent: agent)
    |> Repo.all()
  end

  @spec chatbox_dashboard(map(), integer() | nil) :: dashboard_state()
  def chatbox_dashboard(filters \\ %{}, selected_message_id \\ nil) when is_map(filters) do
    messages = list_chatbox_dashboard_messages(filters)
    selected_message = select_dashboard_message(messages, selected_message_id)

    %{
      messages: messages,
      selected_message_id: selected_message && selected_message.id,
      selected_message: selected_message,
      actor_history: selected_author_history(selected_message),
      recent_actions: list_recent_actions(limit: @default_actions_limit)
    }
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

  @spec reconcile_agent_metrics!(integer()) :: :ok
  defp reconcile_agent_metrics!(agent_id) do
    created_node_ids =
      Node
      |> where([n], n.creator_agent_id == ^agent_id)
      |> select([n], n.id)
      |> Repo.all()

    parent_ids =
      Node
      |> where([n], n.creator_agent_id == ^agent_id and not is_nil(n.parent_id))
      |> select([n], n.parent_id)
      |> Repo.all()
      |> Enum.uniq()

    Enum.each(created_node_ids, &Nodes.refresh_activity_score!/1)
    Enum.each(parent_ids, &Nodes.refresh_parent_child_metrics!/1)

    commented_node_ids =
      Comment
      |> where([c], c.author_agent_id == ^agent_id)
      |> select([c], c.node_id)
      |> Repo.all()
      |> Enum.uniq()

    Enum.each(commented_node_ids, &Nodes.refresh_comment_metrics!/1)
    :ok
  end

  defp maybe_filter_dashboard_query(query, filters) do
    case normalize_optional_query(filters) do
      nil ->
        query

      term ->
        like = "%#{term}%"

        where(
          query,
          [message, human, agent],
          ilike(message.body, ^like) or ilike(coalesce(human.display_name, ""), ^like) or
            ilike(coalesce(human.wallet_address, ""), ^like) or
            ilike(coalesce(agent.label, ""), ^like) or
            ilike(coalesce(agent.wallet_address, ""), ^like)
        )
    end
  end

  defp normalize_limit(value) when is_integer(value) and value > 0,
    do: min(value, @default_dashboard_limit)

  defp normalize_limit(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> min(parsed, @default_dashboard_limit)
      _ -> @default_dashboard_limit
    end
  end

  defp normalize_limit(_value), do: @default_dashboard_limit

  defp normalize_optional_query(filters) do
    filters
    |> Map.get("q", Map.get(filters, :q))
    |> case do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp where_author_ref(query, :human, author_ref) do
    where(query, [message], message.author_human_id == ^author_ref)
  end

  defp where_author_ref(query, :agent, author_ref) do
    where(query, [message], message.author_agent_id == ^author_ref)
  end

  defp select_dashboard_message([], _selected_message_id), do: nil

  defp select_dashboard_message(messages, selected_message_id) do
    Enum.find(messages, &(&1.id == selected_message_id)) || List.first(messages)
  end

  defp selected_author_history(%Message{} = message) do
    case author_ref(message) do
      author_ref when is_integer(author_ref) and author_ref > 0 ->
        list_chatbox_author_history(message.author_kind, author_ref,
          limit: @default_history_limit
        )

      _ ->
        []
    end
  end

  defp selected_author_history(_message), do: []

  defp author_ref(%Message{author_kind: :human, author_human_id: id}), do: id
  defp author_ref(%Message{author_kind: :agent, author_agent_id: id}), do: id

  defp fetch_entity(schema, id, not_found_reason) do
    case Repo.get(schema, normalize_id(id)) do
      nil -> {:error, not_found_reason}
      record -> {:ok, record}
    end
  end
end
