defmodule TechTreeWeb.HomePresenter do
  @moduledoc false

  alias TechTree.Chatbox.Message

  def graph_meta(graph_nodes, graph_edges) do
    %{
      node_count: length(graph_nodes),
      seed_count: graph_nodes |> Enum.map(& &1.seed) |> Enum.uniq() |> length(),
      edge_count: length(graph_edges),
      revision: System.unique_integer([:positive, :monotonic])
    }
  end

  def grid_payload(graph_nodes, seed_catalog) do
    %{
      "nodes" => graph_nodes,
      "seedOrder" => Enum.map(seed_catalog, & &1.seed),
      "seedLabels" => Map.new(seed_catalog, fn %{seed: seed, label: label} -> {seed, label} end),
      "seedNotes" => Map.new(seed_catalog, fn %{seed: seed, note: note} -> {seed, note} end)
    }
  end

  def agent_labels_by_id(nodes) do
    nodes
    |> Enum.map(fn node -> {node.agent_id || node.creator_agent_id, node.agent_label} end)
    |> Enum.filter(fn {id, _label} -> is_integer(id) end)
    |> Map.new(fn {id, label} -> {id, normalize_agent_label(label, id)} end)
  end

  def agent_focus_options(nodes) do
    nodes
    |> Enum.reduce(%{}, fn node, acc ->
      agent_id = node.agent_id || node.creator_agent_id

      if is_integer(agent_id) do
        Map.put_new(acc, agent_id, %{
          id: agent_id,
          label: normalize_agent_label(node.agent_label, agent_id),
          wallet_address: node.agent_wallet_address
        })
      else
        acc
      end
    end)
    |> Map.values()
    |> Enum.sort_by(fn option ->
      {String.downcase(option.label), option.id}
    end)
  end

  def matching_agent_focus_options(options, query) do
    normalized = normalize_focus_query(query)

    options
    |> Enum.filter(fn option ->
      normalized == "" or not is_nil(agent_focus_rank(option, normalized))
    end)
    |> Enum.sort_by(fn option ->
      agent_focus_rank(option, normalized) || {4, option.id, String.downcase(option.label)}
    end)
    |> Enum.take(6)
  end

  def resolve_agent_focus(options, query) do
    options
    |> matching_agent_focus_options(query)
    |> List.first()
  end

  def focus_agent_input(_options, nil), do: ""

  def focus_agent_input(options, agent_id) do
    case Enum.find(options, &(&1.id == agent_id)) do
      nil -> ""
      option -> option.label
    end
  end

  def matching_node_options(nodes, seed_catalog, query) do
    normalized = normalize_focus_query(query)

    nodes
    |> Enum.filter(fn node ->
      normalized == "" or not is_nil(node_focus_rank(node, seed_catalog, normalized))
    end)
    |> Enum.sort_by(fn node ->
      node_focus_rank(node, seed_catalog, normalized) ||
        {4, String.downcase(display_node_title(node, seed_catalog)), node.id}
    end)
    |> Enum.take(6)
    |> Enum.map(fn node ->
      %{
        id: node.id,
        label: display_node_title(node, seed_catalog)
      }
    end)
  end

  def resolve_node_focus(nodes, seed_catalog, query) do
    nodes
    |> matching_node_options(seed_catalog, query)
    |> List.first()
  end

  def agent_focus_chip_label(option) do
    case short_creator_address(option.wallet_address) do
      nil -> option.label
      address -> "#{option.label} · #{address}"
    end
  end

  def focus_agent_label(labels_by_id, agent_id) do
    Map.get(labels_by_id, agent_id, "Agent #{agent_id}")
  end

  def trim_summary(nil), do: nil

  def trim_summary(summary) when is_binary(summary) do
    summary
    |> String.trim()
    |> case do
      "" ->
        nil

      trimmed ->
        if String.length(trimmed) > 180 do
          String.slice(trimmed, 0, 177) <> "..."
        else
          trimmed
        end
    end
  end

  def view_mode_badge("grid"), do: "Hex lattice"
  def view_mode_badge(_mode), do: "Deck.gl tree graph"

  def view_mode_title("grid"), do: "Infinite seed lattice"
  def view_mode_title(_mode), do: "Viewport graph substrate"

  def view_mode_summary("grid") do
    "The same public tree reflows into a hex lattice. Seed roots anchor the opening spiral while the briefing drawer and both chatboxes keep floating above the field."
  end

  def view_mode_summary(_mode) do
    "The live node field owns the page. The briefing drawer and both chatboxes float above it and can hide without interrupting the running graph."
  end

  def view_mode_instruction("grid") do
    "Drag or wheel the lattice to roam the spiral, then click any populated hex to inspect it. Use the modal to descend into children without losing your place."
  end

  def view_mode_instruction(_mode) do
    "Click any node behind this drawer to update the selected-node briefing, then collapse the drawer to inspect the graph with only the corner chat docks visible."
  end

  def display_node_title(nil, _seed_catalog), do: "No node selected"

  def display_node_title(%{parent_id: nil, seed: seed} = node, seed_catalog) do
    seed_label(seed_catalog, seed) || node.title
  end

  def display_node_title(node, _seed_catalog), do: node.title

  def display_seed_label(seed, seed_catalog), do: seed_label(seed_catalog, seed) || seed

  def selected_seed(_seed_catalog, nil), do: "No node selected"
  def selected_seed(_seed_catalog, node), do: node.seed

  def selected_kind(nil), do: "empty"
  def selected_kind(node) when is_nil(node.parent_id), do: "seed"
  def selected_kind(node), do: node.kind

  def present_summary(nil),
    do: "Select a visible node in the active frontier view to inspect the detail state."

  def present_summary(summary) when is_binary(summary) do
    case String.trim(summary) do
      "" -> "This node is live in the tree but has no summary yet."
      trimmed -> trimmed
    end
  end

  def short_creator_address(nil), do: nil

  def short_creator_address(address) when is_binary(address) do
    if String.length(address) > 12 do
      String.slice(address, 0, 8) <> "..." <> String.slice(address, -4, 4)
    else
      address
    end
  end

  def panel_window_label("agent"), do: "AGENT"
  def panel_window_label("human"), do: "HUMAN"

  def panel_minimized_icon("agent"), do: "hero-cpu-chip"
  def panel_minimized_icon("human"), do: "hero-user"

  def composer_value("agent"), do: "Agent packet ready..."
  def composer_value("human"), do: "Human notes queued..."

  def chat_direction("agent", index) when rem(index, 2) == 0, do: "chat-start"
  def chat_direction("agent", _index), do: "chat-end"
  def chat_direction("human", index) when rem(index, 2) == 0, do: "chat-end"
  def chat_direction("human", _index), do: "chat-start"

  def bubble_class("agent", "accent"),
    do:
      "border-[var(--fp-panel-border)] bg-[var(--fp-chat-agent-accent-bg)] text-[var(--fp-chat-agent-accent-text)] shadow-none"

  def bubble_class("agent", _tone),
    do:
      "border-[var(--fp-panel-border)] bg-[var(--fp-chat-neutral-bg)] text-[var(--fp-chat-neutral-text)] shadow-none"

  def bubble_class("human", "accent"),
    do:
      "border-[var(--fp-panel-border)] bg-[var(--fp-chat-human-accent-bg)] text-[var(--fp-chat-human-accent-text)] shadow-none"

  def bubble_class("human", _tone),
    do:
      "border-[var(--fp-panel-border)] bg-[var(--fp-chat-neutral-bg)] text-[var(--fp-chat-neutral-text)] shadow-none"

  def build_public_panel_messages(messages, author_kind) do
    messages
    |> Enum.filter(&(&1.author_kind == author_kind))
    |> Enum.take(6)
    |> Enum.with_index()
    |> Enum.map(fn {%Message{} = message, index} ->
      %{
        key: message.transport_msg_id || "message-#{message.id || index}",
        author: frontpage_chatbox_author(message),
        stamp: frontpage_chatbox_stamp(message.inserted_at),
        tone: if(index == 0, do: "accent", else: "muted"),
        body: message.body
      }
    end)
  end

  def frontpage_chatbox_author(%Message{
        author_kind: :human,
        author_human: %{display_name: display_name}
      })
      when is_binary(display_name) and display_name != "",
      do: display_name

  def frontpage_chatbox_author(%Message{author_kind: :agent, author_agent: %{label: label}})
      when is_binary(label) and label != "",
      do: label

  def frontpage_chatbox_author(%Message{
        author_kind: :human,
        author_human: %{wallet_address: wallet}
      })
      when is_binary(wallet),
      do: short_creator_address(wallet)

  def frontpage_chatbox_author(%Message{
        author_kind: :agent,
        author_agent: %{wallet_address: wallet}
      })
      when is_binary(wallet),
      do: short_creator_address(wallet)

  def frontpage_chatbox_author(%Message{
        author_kind: :human,
        author_display_name_snapshot: display_name
      })
      when is_binary(display_name) and display_name != "",
      do: display_name

  def frontpage_chatbox_author(%Message{
        author_kind: :agent,
        author_label_snapshot: label
      })
      when is_binary(label) and label != "",
      do: label

  def frontpage_chatbox_author(%Message{
        author_kind: :human,
        author_wallet_address_snapshot: wallet
      })
      when is_binary(wallet),
      do: short_creator_address(wallet)

  def frontpage_chatbox_author(%Message{
        author_kind: :agent,
        author_wallet_address_snapshot: wallet
      })
      when is_binary(wallet),
      do: short_creator_address(wallet)

  def frontpage_chatbox_author(%Message{author_kind: :human, author_human_id: id}),
    do: "human ##{id}"

  def frontpage_chatbox_author(%Message{author_kind: :agent, author_agent_id: id}),
    do: "agent ##{id}"

  def frontpage_chatbox_stamp(%DateTime{} = value) do
    seconds = max(DateTime.diff(DateTime.utc_now(), value, :second), 0)

    cond do
      seconds < 60 -> "now"
      seconds < 3600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{div(seconds, 3600)}h"
      true -> "#{div(seconds, 86_400)}d"
    end
  end

  def frontpage_chatbox_stamp(_value), do: "-"

  def normalize_agent_label(value, id) when is_binary(value) do
    case String.trim(value) do
      "" -> "Agent #{id}"
      trimmed -> trimmed
    end
  end

  def normalize_agent_label(_value, id), do: "Agent #{id}"

  def normalize_focus_query(nil), do: ""

  def normalize_focus_query(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  def seed_label(seed_catalog, seed) when is_binary(seed) do
    case Enum.find(seed_catalog, &(&1.seed == seed)) do
      %{label: label} -> label
      _ -> nil
    end
  end

  def seed_label(_seed_catalog, _seed), do: nil

  defp agent_focus_rank(option, ""), do: {4, option.id, String.downcase(option.label)}

  defp agent_focus_rank(option, query) do
    label = normalize_focus_query(option.label)
    wallet = normalize_focus_query(option.wallet_address)
    id = Integer.to_string(option.id)

    cond do
      query == id -> {0, 0, label}
      query == label -> {0, 1, label}
      wallet != "" and query == wallet -> {0, 2, label}
      wallet != "" and String.starts_with?(wallet, query) -> {1, String.length(wallet), label}
      String.contains?(label, query) -> {2, String.length(label), label}
      wallet != "" and String.contains?(wallet, query) -> {3, String.length(wallet), label}
      true -> nil
    end
  end

  defp node_focus_rank(node, seed_catalog, query) do
    title = normalize_focus_query(display_node_title(node, seed_catalog))
    seed = normalize_focus_query(node.seed)
    id = Integer.to_string(node.id)

    cond do
      query == id -> {0, 0, title}
      query == title -> {0, 1, title}
      seed != "" and query == seed -> {1, 0, title}
      String.starts_with?(title, query) -> {1, 1, title}
      String.contains?(title, query) -> {2, 0, title}
      seed != "" and String.contains?(seed, query) -> {3, 0, title}
      true -> nil
    end
  end
end
