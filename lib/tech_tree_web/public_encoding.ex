defmodule TechTreeWeb.PublicEncoding do
  @moduledoc false

  alias TechTree.Activity.ActivityEvent
  alias TechTree.Comments.Comment
  alias TechTree.Nodes.{Node, NodeTagEdge}
  alias TechTree.Watches.NodeWatcher
  alias TechTree.XMTPMirror.XmtpMessage

  @spec encode_nodes([Node.t()]) :: [map()]
  def encode_nodes(nodes) when is_list(nodes), do: Enum.map(nodes, &encode_node/1)

  @spec encode_node(Node.t()) :: map()
  def encode_node(%Node{} = node) do
    %{
      id: node.id,
      parent_id: node.parent_id,
      path: node.path,
      depth: node.depth,
      seed: node.seed,
      kind: enum_to_string(node.kind),
      title: node.title,
      slug: node.slug,
      summary: node.summary,
      status: enum_to_string(node.status),
      manifest_uri: node.manifest_uri,
      manifest_hash: node.manifest_hash,
      notebook_cid: node.notebook_cid,
      skill_slug: node.skill_slug,
      skill_version: node.skill_version,
      child_count: node.child_count,
      comment_count: node.comment_count,
      watcher_count: node.watcher_count,
      activity_score: node.activity_score,
      comments_locked: node.comments_locked,
      inserted_at: node.inserted_at,
      updated_at: node.updated_at,
      sidelinks: encode_preloaded_tag_edges(node.tag_edges_out)
    }
    |> maybe_put_creator_agent(node)
  end

  @spec encode_tag_edges([NodeTagEdge.t()]) :: [map()]
  def encode_tag_edges(edges) when is_list(edges), do: Enum.map(edges, &encode_tag_edge/1)

  @spec encode_tag_edge(NodeTagEdge.t()) :: map()
  def encode_tag_edge(%NodeTagEdge{} = edge) do
    %{
      id: edge.id,
      src_node_id: edge.src_node_id,
      dst_node_id: edge.dst_node_id,
      tag: edge.tag,
      ordinal: edge.ordinal
    }
  end

  @spec encode_comments([Comment.t()]) :: [map()]
  def encode_comments(comments) when is_list(comments), do: Enum.map(comments, &encode_comment/1)

  @spec encode_comment(Comment.t()) :: map()
  def encode_comment(%Comment{} = comment) do
    %{
      id: comment.id,
      node_id: comment.node_id,
      author_agent_id: comment.author_agent_id,
      body_markdown: comment.body_markdown,
      body_plaintext: comment.body_plaintext,
      body_cid: comment.body_cid,
      status: enum_to_string(comment.status),
      inserted_at: comment.inserted_at
    }
  end

  @spec encode_activity_events([ActivityEvent.t()]) :: [map()]
  def encode_activity_events(events) when is_list(events),
    do: Enum.map(events, &encode_activity_event/1)

  @spec encode_activity_event(ActivityEvent.t()) :: map()
  def encode_activity_event(%ActivityEvent{} = event) do
    %{
      id: event.id,
      subject_node_id: event.subject_node_id,
      actor_type: enum_to_string(event.actor_type),
      actor_ref: event.actor_ref,
      event_type: event.event_type,
      payload: event.payload,
      inserted_at: event.inserted_at
    }
  end

  @spec encode_messages([XmtpMessage.t()]) :: [map()]
  def encode_messages(messages) when is_list(messages), do: Enum.map(messages, &encode_message/1)

  @spec encode_message(XmtpMessage.t()) :: map()
  def encode_message(%XmtpMessage{} = message) do
    %{
      id: message.id,
      room_id: message.room_id,
      xmtp_message_id: message.xmtp_message_id,
      sender_inbox_id: message.sender_inbox_id,
      sender_wallet_address: message.sender_wallet_address,
      sender_label: message.sender_label,
      sender_type: enum_to_string(message.sender_type),
      body: message.body,
      sent_at: message.sent_at,
      moderation_state: message.moderation_state,
      inserted_at: message.inserted_at
    }
  end

  @spec encode_watch(NodeWatcher.t()) :: map()
  def encode_watch(%NodeWatcher{} = watch) do
    %{
      id: watch.id,
      node_id: watch.node_id,
      watcher_type: enum_to_string(watch.watcher_type),
      watcher_ref: watch.watcher_ref,
      inserted_at: watch.inserted_at
    }
  end

  @spec encode_search_results(map()) :: map()
  def encode_search_results(%{nodes: nodes, comments: comments}) do
    %{
      nodes: encode_nodes(nodes),
      comments: encode_comments(comments)
    }
  end

  @spec maybe_put_creator_agent(map(), Node.t()) :: map()
  defp maybe_put_creator_agent(base, %Node{creator_agent: creator_agent}) do
    if Ecto.assoc_loaded?(creator_agent) and not is_nil(creator_agent) do
      Map.put(base, :creator_agent, %{
        id: creator_agent.id,
        label: creator_agent.label,
        wallet_address: creator_agent.wallet_address
      })
    else
      base
    end
  end

  @spec encode_preloaded_tag_edges(term()) :: [map()]
  defp encode_preloaded_tag_edges(edges) when is_list(edges), do: encode_tag_edges(edges)
  defp encode_preloaded_tag_edges(_), do: []

  @spec enum_to_string(atom() | String.t() | nil) :: String.t() | nil
  defp enum_to_string(nil), do: nil
  defp enum_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_to_string(value) when is_binary(value), do: value
end
