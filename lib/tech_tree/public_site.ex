defmodule TechTree.PublicSite do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Activity
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Autoskill.NodeBundle
  alias TechTree.HumanUX
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.PublicSite.BBHPage
  alias TechTree.PublicSite.LearnPage
  alias TechTree.PublicSite.StartPage
  alias TechTree.Repo
  alias TechTree.Stars.NodeStar
  alias TechTree.XMTPMirror
  alias TechTreeWeb.HomePresenter

  @spec install_command() :: String.t()
  defdelegate install_command, to: StartPage

  @spec start_command() :: String.t()
  defdelegate start_command, to: StartPage

  @spec ios_app_url() :: String.t()
  defdelegate ios_app_url, to: StartPage

  @spec install_agents() :: [map()]
  defdelegate install_agents, to: StartPage

  @spec find_install_agent(String.t() | nil) :: map()
  defdelegate find_install_agent(agent_id), to: StartPage

  @spec learn_topics() :: [map()]
  defdelegate learn_topics, to: LearnPage, as: :topics

  @spec learn_topic(String.t() | nil) :: map() | nil
  defdelegate learn_topic(topic_id), to: LearnPage, as: :topic

  @spec learn_path_steps() :: [map()]
  defdelegate learn_path_steps, to: LearnPage, as: :path_steps

  @spec landing_signal_items() :: [map()]
  def landing_signal_items do
    latest_row = List.first(latest_agent_activity_rows(1))
    branch_count = HumanUX.seed_lanes() |> Enum.map(& &1.branch_count) |> Enum.sum()
    notebooks_count = length(notebook_cards(3))
    room_message_count = combined_room_messages(6) |> length()

    [
      %{
        id: "latest-action",
        label: "Latest public move",
        value: latest_signal_value(latest_row),
        copy: latest_signal_copy(latest_row),
        href: latest_row && latest_row.href
      },
      %{
        id: "visible-branches",
        label: "Visible branches",
        value: Integer.to_string(branch_count),
        copy: "Public branches are already moving across the live tree.",
        href: "/tree"
      },
      %{
        id: "public-room",
        label: "Public room",
        value: Integer.to_string(room_message_count),
        copy: "Recent public handoffs stay visible beside the tree view.",
        href: "/tree"
      },
      %{
        id: "notebooks",
        label: "Notebook gallery",
        value: Integer.to_string(notebooks_count),
        copy: "Top starred marimo notebooks are ready to browse.",
        href: "/notebooks"
      }
    ]
  end

  @spec latest_agent_activity_rows(pos_integer()) :: [map()]
  def latest_agent_activity_rows(limit \\ 10) when is_integer(limit) and limit > 0 do
    events = Activity.list_public_agent_events(%{"limit" => Integer.to_string(limit)})

    agent_labels_by_id =
      events
      |> Enum.map(& &1.actor_ref)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> then(fn agent_ids ->
        Repo.all(
          from agent in AgentIdentity,
            where: agent.id in ^agent_ids,
            select: {agent.id, agent.label}
        )
      end)
      |> Map.new(fn {id, label} -> {id, HomePresenter.normalize_agent_label(label, id)} end)

    nodes_by_id =
      events
      |> Enum.flat_map(&HomePresenter.referenced_node_ids/1)
      |> Enum.uniq()
      |> Nodes.list_public_nodes_by_ids()
      |> Map.new(&{&1.id, &1})

    HomePresenter.landing_activity_rows(events, agent_labels_by_id, nodes_by_id)
    |> Enum.map(fn row ->
      %{row | href: if(row.href, do: String.replace_prefix(row.href, "/node/", "/tree/node/"))}
    end)
  end

  @spec recent_node_cards(pos_integer()) :: [map()]
  def recent_node_cards(limit \\ 6) when is_integer(limit) and limit > 0 do
    Nodes.list_recent_public_nodes(%{"limit" => Integer.to_string(limit)})
    |> Enum.map(&node_card/1)
  end

  @spec popular_node_cards(pos_integer()) :: [map()]
  def popular_node_cards(limit \\ 6) when is_integer(limit) and limit > 0 do
    Nodes.list_public_nodes(%{"limit" => Integer.to_string(limit)})
    |> Enum.map(&node_card/1)
  end

  @spec featured_branch_cards(pos_integer()) :: [map()]
  def featured_branch_cards(limit \\ 5) when is_integer(limit) and limit > 0 do
    HumanUX.seed_lanes()
    |> Enum.take(limit)
    |> Enum.map(fn lane ->
      top_branch = List.first(lane.branches)

      %{
        id: lane.seed,
        seed: lane.seed,
        title: lane.top_title,
        summary: HomePresenter.trim_summary(lane.top_summary) || "No public summary yet.",
        href: "/tree/seed/#{lane.seed}",
        branch_count: lane.branch_count,
        top_branch_href: if(top_branch, do: "/tree/node/#{top_branch.id}", else: nil),
        top_branch_title: if(top_branch, do: top_branch.title, else: nil)
      }
    end)
  end

  @spec notebook_cards(pos_integer()) :: [map()]
  def notebook_cards(limit \\ 6) when is_integer(limit) and limit > 0 do
    Repo.all(
      from node in Node,
        join: creator in AgentIdentity,
        on: creator.id == node.creator_agent_id,
        join: bundle in NodeBundle,
        on: bundle.node_id == node.id,
        left_join: star in NodeStar,
        on: star.node_id == node.id,
        where:
          node.status == :anchored and creator.status == "active" and
            not is_nil(bundle.marimo_entrypoint),
        group_by: [
          node.id,
          node.seed,
          node.title,
          node.summary,
          node.activity_score,
          node.inserted_at,
          node.watcher_count,
          creator.label,
          bundle.primary_file,
          bundle.marimo_entrypoint
        ],
        order_by: [
          desc: count(star.id),
          desc: node.activity_score,
          desc: node.inserted_at,
          desc: node.id
        ],
        limit: ^limit,
        select: %{
          id: node.id,
          seed: node.seed,
          title: node.title,
          summary: node.summary,
          watcher_count: node.watcher_count,
          inserted_at: node.inserted_at,
          creator_label: creator.label,
          primary_file: bundle.primary_file,
          marimo_entrypoint: bundle.marimo_entrypoint,
          star_count: count(star.id)
        }
    )
    |> Enum.map(fn notebook ->
      %{
        id: notebook.id,
        seed: notebook.seed,
        title: notebook.title,
        summary: HomePresenter.trim_summary(notebook.summary) || "No notebook summary yet.",
        href: "/tree/node/#{notebook.id}",
        branch_href: "/tree/node/#{notebook.id}",
        creator: notebook.creator_label || "Unknown agent",
        stars: notebook.star_count,
        watchers: notebook.watcher_count,
        age: HomePresenter.frontpage_chatbox_stamp(notebook.inserted_at),
        primary_file: notebook.primary_file || "session.marimo.py",
        marimo_entrypoint: notebook.marimo_entrypoint
      }
    end)
  end

  @spec room_panels(pos_integer()) :: %{human: [map()], agent: [map()]}
  def room_panels(limit \\ 16) when is_integer(limit) and limit > 0 do
    messages = XMTPMirror.list_public_messages(%{"limit" => Integer.to_string(limit)})

    %{
      human:
        messages |> Enum.reject(&(&1.sender_type == :agent)) |> Enum.map(&xmtp_message_card/1),
      agent:
        messages |> Enum.filter(&(&1.sender_type == :agent)) |> Enum.map(&xmtp_message_card/1)
    }
  end

  @spec combined_room_messages(pos_integer()) :: [map()]
  def combined_room_messages(limit \\ 10) when is_integer(limit) and limit > 0 do
    messages = XMTPMirror.list_public_messages(%{"limit" => Integer.to_string(limit)})

    messages
    |> Enum.take(limit)
    |> Enum.map(&xmtp_message_card/1)
  end

  @spec notebook_collections(pos_integer()) :: [map()]
  def notebook_collections(limit \\ 3) when is_integer(limit) and limit > 0 do
    notebook_cards(18)
    |> Enum.group_by(& &1.seed)
    |> Enum.map(fn {seed, cards} ->
      lead = List.first(cards)

      %{
        id: seed,
        label: seed,
        count: length(cards),
        title: "#{seed} notebooks",
        copy:
          "#{lead.title} leads this collection, with public notebook work ready to open from the live tree.",
        href: lead.branch_href
      }
    end)
    |> Enum.sort_by(fn collection -> {-collection.count, collection.label} end)
    |> Enum.take(limit)
  end

  @spec bbh_snapshot() :: map()
  defdelegate bbh_snapshot, to: BBHPage, as: :snapshot

  @spec bbh_flow_steps() :: [map()]
  defdelegate bbh_flow_steps, to: BBHPage, as: :flow_steps

  defp node_card(%Node{} = node) do
    %{
      id: node.id,
      seed: node.seed,
      kind: node.kind,
      title: node.title,
      summary: HomePresenter.trim_summary(node.summary) || "No public summary yet.",
      href: "/tree/node/#{node.id}",
      seed_href: "/tree/seed/#{node.seed}",
      watchers: node.watcher_count,
      comments: node.comment_count,
      activity: format_activity(node.activity_score),
      age: HomePresenter.frontpage_chatbox_stamp(node.inserted_at)
    }
  end

  defp format_activity(nil), do: "0.0"
  defp format_activity(score), do: score |> Decimal.round(1) |> Decimal.to_string(:normal)

  defp xmtp_message_card(message) do
    sender_type = message.sender_type || :human

    %{
      key: message.xmtp_message_id || "xmtp-message-#{message.id}",
      room: if(sender_type == :agent, do: "Agent room", else: "Human room"),
      author: xmtp_author(message),
      stamp: HomePresenter.frontpage_chatbox_stamp(message.sent_at),
      body: message.body
    }
  end

  defp xmtp_author(%{sender_label: label}) when is_binary(label) and label != "", do: label
  defp xmtp_author(%{sender_type: :agent}), do: "Agent"
  defp xmtp_author(_message), do: "Human"

  defp latest_signal_value(nil), do: "Waiting"
  defp latest_signal_value(row), do: row.action

  defp latest_signal_copy(nil), do: "The next visible agent action will appear here."

  defp latest_signal_copy(row) do
    "#{row.agent} touched #{row.subject} #{row.time}."
  end
end
