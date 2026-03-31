defmodule TechTreeWeb.PublicEncoding do
  @moduledoc false

  alias TechTree.Activity
  alias TechTree.Activity.ActivityEvent
  alias TechTree.Comments.Comment
  alias TechTree.Nodes.{Node, NodeTagEdge}
  alias TechTree.Chatbox.Message
  alias TechTree.Watches.NodeWatcher

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
      manifest_cid: node.manifest_cid,
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
    |> maybe_put_cross_chain_lineage(node)
    |> maybe_put_autoskill(node)
    |> maybe_put_paid_payload(node)
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
      stream: event |> Activity.classify_stream() |> Atom.to_string(),
      payload: event.payload,
      inserted_at: event.inserted_at
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

  @spec encode_watches([NodeWatcher.t()]) :: [map()]
  def encode_watches(watches) when is_list(watches), do: Enum.map(watches, &encode_watch/1)

  @spec encode_star(TechTree.Stars.NodeStar.t()) :: map()
  def encode_star(%TechTree.Stars.NodeStar{} = star) do
    %{
      id: star.id,
      node_id: star.node_id,
      actor_type: enum_to_string(star.actor_type),
      actor_ref: star.actor_ref,
      inserted_at: star.inserted_at
    }
  end

  @spec encode_search_results(map()) :: map()
  def encode_search_results(%{nodes: nodes, comments: comments}) do
    %{
      nodes: encode_nodes(nodes),
      comments: encode_comments(comments)
    }
  end

  @spec encode_node_work_packet(%{
          node: Node.t(),
          comments: [Comment.t()],
          activity_events: [ActivityEvent.t()]
        }) :: map()
  def encode_node_work_packet(%{node: node, comments: comments, activity_events: activity_events}) do
    %{
      node: encode_node(node),
      comments: encode_comments(comments),
      activity_events: encode_activity_events(activity_events)
    }
  end

  @spec encode_agent_inbox(%{
          events: [ActivityEvent.t()],
          next_cursor: integer() | nil
        }) :: %{
          events: [map()],
          next_cursor: integer() | nil
        }
  def encode_agent_inbox(%{events: events, next_cursor: next_cursor}) do
    %{
      events: encode_activity_events(events),
      next_cursor: next_cursor
    }
  end

  @spec encode_opportunities([map()]) :: [map()]
  def encode_opportunities(opportunities) when is_list(opportunities) do
    Enum.map(opportunities, fn opportunity ->
      opportunity
      |> Map.new(fn {key, value} -> {key, encode_opportunity_value(value)} end)
    end)
  end

  @spec encode_chatbox_messages([Message.t()]) :: [map()]
  def encode_chatbox_messages(messages) when is_list(messages),
    do: Enum.map(messages, &encode_chatbox_message/1)

  @spec encode_chatbox_message(Message.t()) :: map()
  def encode_chatbox_message(%Message{} = message) do
    %{
      id: message.id,
      room_id: message.room_id || "global",
      transport_msg_id: message.transport_msg_id,
      transport_topic: message.transport_topic,
      origin_peer_id: message.origin_peer_id,
      origin_node_id: message.origin_node_id,
      author_kind: enum_to_string(message.author_kind),
      author_human_id: message.author_human_id,
      author_agent_id: message.author_agent_id,
      author_display_name: encode_human_display_name(message),
      author_label: encode_agent_label(message),
      author_wallet_address: encode_author_wallet_address(message),
      author_transport_id: message.author_transport_id,
      body: message.body,
      client_message_id: message.client_message_id,
      reply_to_message_id: message.reply_to_message_id,
      reply_to_transport_msg_id: message.reply_to_transport_msg_id,
      reactions: message.reactions || %{},
      moderation_state: message.moderation_state,
      sent_at: message.inserted_at,
      inserted_at: message.inserted_at,
      updated_at: message.updated_at
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

  @spec maybe_put_cross_chain_lineage(map(), Node.t()) :: map()
  defp maybe_put_cross_chain_lineage(base, %Node{cross_chain_lineage: nil}), do: base

  defp maybe_put_cross_chain_lineage(base, %Node{cross_chain_lineage: cross_chain_lineage})
       when is_map(cross_chain_lineage) do
    Map.put(base, :cross_chain_lineage, cross_chain_lineage)
  end

  defp maybe_put_cross_chain_lineage(base, _node), do: base

  @spec maybe_put_autoskill(map(), Node.t()) :: map()
  defp maybe_put_autoskill(base, %Node{autoskill: nil}), do: base

  defp maybe_put_autoskill(base, %Node{autoskill: autoskill}) when is_map(autoskill) do
    Map.put(base, :autoskill, autoskill)
  end

  defp maybe_put_autoskill(base, _node), do: base

  @spec maybe_put_paid_payload(map(), Node.t()) :: map()
  defp maybe_put_paid_payload(base, %Node{paid_payload: nil}), do: base

  defp maybe_put_paid_payload(base, %Node{paid_payload: paid_payload})
       when is_map(paid_payload) do
    Map.put(base, :paid_payload, paid_payload)
  end

  defp maybe_put_paid_payload(base, _node), do: base

  @spec encode_preloaded_tag_edges(term()) :: [map()]
  defp encode_preloaded_tag_edges(edges) when is_list(edges), do: encode_tag_edges(edges)
  defp encode_preloaded_tag_edges(_), do: []

  defp encode_human_display_name(%Message{author_human: %{display_name: display_name}})
       when is_binary(display_name) and display_name != "",
       do: display_name

  defp encode_human_display_name(%Message{author_display_name_snapshot: display_name})
       when is_binary(display_name) and display_name != "",
       do: display_name

  defp encode_human_display_name(_value), do: nil

  defp encode_agent_label(%Message{author_agent: %{label: label}})
       when is_binary(label) and label != "",
       do: label

  defp encode_agent_label(%Message{author_label_snapshot: label})
       when is_binary(label) and label != "",
       do: label

  defp encode_agent_label(_value), do: nil

  defp encode_author_wallet_address(%Message{author_human: %{wallet_address: wallet}})
       when is_binary(wallet),
       do: wallet

  defp encode_author_wallet_address(%Message{author_agent: %{wallet_address: wallet}})
       when is_binary(wallet),
       do: wallet

  defp encode_author_wallet_address(%Message{author_wallet_address_snapshot: wallet})
       when is_binary(wallet),
       do: wallet

  defp encode_author_wallet_address(_message), do: nil

  @spec enum_to_string(atom() | String.t() | nil) :: String.t() | nil
  defp enum_to_string(nil), do: nil
  defp enum_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_to_string(value) when is_binary(value), do: value

  @spec encode_opportunity_value(term()) :: term()
  defp encode_opportunity_value(%Decimal{} = value), do: Decimal.to_string(value)
  defp encode_opportunity_value(value), do: value
end
