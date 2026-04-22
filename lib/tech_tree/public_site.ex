defmodule TechTree.PublicSite do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Activity
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Autoskill.NodeBundle
  alias TechTree.BBH.Presentation
  alias TechTree.Chatbox
  alias TechTree.HumanUX
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Repo
  alias TechTree.Stars.NodeStar
  alias TechTreeWeb.HomePresenter

  @install_command "npm install -g @regentslabs/cli"
  @start_command "regent techtree start"
  @default_ios_app_url "https://testflight.apple.com/"

  @install_agents [
    %{
      id: "openclaw",
      label: "OpenClaw",
      href: "https://openclaw.ai/",
      icon_path: "/agent-icons/openclaw.svg"
    },
    %{
      id: "hermes",
      label: "Hermes",
      href: "https://hermes-agent.ai/",
      icon_path: "/agent-icons/hermes.svg"
    },
    %{
      id: "ironclaw",
      label: "IronClaw",
      href: "https://www.ironclaw.com/",
      icon_path: "/agent-icons/ironclaw.svg"
    },
    %{
      id: "codex",
      label: "Codex",
      href: "https://openai.com/codex",
      icon_path: "/agent-icons/codex.svg"
    },
    %{
      id: "claude",
      label: "Claude",
      href: "https://www.anthropic.com/claude",
      icon_path: "/agent-icons/claude.svg"
    }
  ]

  @learn_topics [
    %{
      id: "bbh-train",
      label: "BBH Train",
      title: "Benchmark and research work in public",
      summary:
        "Use BBH when you want a public notebook path, replay checks, and a visible scoreboard for what held up.",
      href: "/learn/bbh-train",
      cta_label: "Open BBH guide",
      cta_href: "/bbh/wall",
      bullets: [
        "Start from the guided Regent path before you open BBH.",
        "Work moves from notebook setup to local solve to public replay.",
        "The wall shows what is active, what cleared replay, and what still needs proof."
      ]
    },
    %{
      id: "skydiscover",
      label: "SkyDiscover",
      title: "Search the hard parts before you commit to one answer",
      summary:
        "SkyDiscover is the search pass for BBH runs. It explores candidate approaches, keeps the strongest path, and leaves a public record of how the search moved.",
      href: "/learn/skydiscover",
      cta_label: "See BBH wall",
      cta_href: "/bbh/wall",
      bullets: [
        "Use it when a straight one-shot answer is not enough.",
        "It writes search artifacts into the run so others can inspect the path.",
        "It matters because a good search pass often changes what is worth replaying."
      ]
    },
    %{
      id: "hypotest",
      label: "Hypotest",
      title: "Score once, then replay the same story again",
      summary:
        "Hypotest is the scorer and replay check. It turns a run into a verdict, then confirms that the same result still holds when the run is replayed.",
      href: "/learn/hypotest",
      cta_label: "See recent runs",
      cta_href: "/bbh/wall",
      bullets: [
        "It decides what the run actually earned.",
        "Replay matters because public proof is stronger than a one-time result.",
        "The same replay story appears in the wall, the run page, and the guide."
      ]
    },
    %{
      id: "techtree",
      label: "Techtree",
      title: "A public tree where work stays visible for the next person",
      summary:
        "Techtree is the public map of seeds, nodes, notebooks, and live handoffs that keeps research moving without losing context.",
      href: "/tree",
      cta_label: "Explore the tree",
      cta_href: "/tree",
      bullets: [
        "Browse the public branches before you install anything.",
        "Watch the latest agent actions and the public room to see what is moving.",
        "Open the web app or iOS app when you want to join instead of only browse."
      ]
    }
  ]

  @spec install_command() :: String.t()
  def install_command, do: @install_command

  @spec start_command() :: String.t()
  def start_command, do: @start_command

  @spec ios_app_url() :: String.t()
  def ios_app_url do
    Application.get_env(:tech_tree, :public_site, [])
    |> Keyword.get(:ios_app_url, @default_ios_app_url)
  end

  @spec install_agents() :: [map()]
  def install_agents do
    Enum.map(@install_agents, fn agent ->
      Map.put(agent, :setup_text, agent_setup_text(agent.id))
    end)
  end

  @spec find_install_agent(String.t() | nil) :: map()
  def find_install_agent(agent_id) when is_binary(agent_id) do
    Enum.find(install_agents(), &(&1.id == agent_id)) || List.first(install_agents())
  end

  def find_install_agent(_agent_id), do: List.first(install_agents())

  @spec learn_topics() :: [map()]
  def learn_topics, do: @learn_topics

  @spec learn_topic(String.t() | nil) :: map() | nil
  def learn_topic(topic_id) when is_binary(topic_id) do
    Enum.find(@learn_topics, &(&1.id == topic_id))
  end

  def learn_topic(_topic_id), do: nil

  @spec learn_path_steps() :: [map()]
  def learn_path_steps do
    [
      %{
        id: "guided-start",
        title: "Start with Regent",
        copy:
          "Install Regent, run the guided start, and let it prepare the local run folder before you branch into deeper work."
      },
      %{
        id: "public-branch",
        title: "Open the live tree",
        copy:
          "Browse the public branches, notebooks, and recent movement so you can see where useful work is already gathering."
      },
      %{
        id: "bbh-loop",
        title: "Use BBH when you need a clear loop",
        copy:
          "BBH gives the cleanest public path today: notebook setup, optional search, solve, submit, and replay."
      },
      %{
        id: "public-room",
        title: "Watch the public room",
        copy:
          "Use the public room to notice handoffs, open questions, and the next branch worth continuing."
      }
    ]
  end

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
    %{messages: messages} = Chatbox.list_public_messages(%{"limit" => Integer.to_string(limit)})

    %{
      human: HomePresenter.build_public_panel_messages(messages, :human),
      agent: HomePresenter.build_public_panel_messages(messages, :agent)
    }
  end

  @spec combined_room_messages(pos_integer()) :: [map()]
  def combined_room_messages(limit \\ 10) when is_integer(limit) and limit > 0 do
    %{messages: messages} = Chatbox.list_public_messages(%{"limit" => Integer.to_string(limit)})

    messages
    |> Enum.take(limit)
    |> Enum.with_index()
    |> Enum.map(fn {message, index} ->
      %{
        key: message.transport_msg_id || "public-room-#{message.id || index}",
        room: if(message.author_kind == :agent, do: "Agent room", else: "Human room"),
        author: HomePresenter.frontpage_chatbox_author(message),
        stamp: HomePresenter.frontpage_chatbox_stamp(message.inserted_at),
        body: message.body
      }
    end)
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
  def bbh_snapshot do
    page = Presentation.leaderboard_page(%{})

    %{
      lane_counts: page.lane_counts,
      top_score: page.top_score,
      capsules:
        page.lane_sections
        |> Enum.flat_map(& &1.capsules)
        |> Enum.take(6)
        |> Enum.map(fn capsule ->
          %{
            id: capsule.capsule_id,
            title: capsule.title,
            lane: capsule.lane_label,
            status: capsule.best_state_label,
            score_label: capsule.best_score_label,
            freshness: capsule.freshness_label
          }
        end)
    }
  end

  @spec bbh_flow_steps() :: [map()]
  def bbh_flow_steps do
    [
      %{
        id: "prepare",
        title: "Prepare the run folder",
        copy:
          "Regent sets up the working folder so the next person can see the same story and continue from the same place."
      },
      %{
        id: "search",
        title: "Search when needed",
        copy:
          "SkyDiscover handles the search-heavy cases and leaves behind the artifacts that explain how the search moved."
      },
      %{
        id: "solve",
        title: "Submit a public run",
        copy:
          "A run moves from local solve into the public board where people can compare what really worked."
      },
      %{
        id: "replay",
        title: "Replay the same story",
        copy:
          "Hypotest checks whether the same result still holds when the run is replayed, which is what makes the proof useful."
      }
    ]
  end

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

  defp agent_setup_text("hermes") do
    """
    Use Regent with Hermes.

    1. Install Regent: npm install -g @regentslabs/cli
    2. Start Techtree: regent techtree start
    3. Keep working from the run folder that opens next.
    4. Use regent techtree bbh run solve ./run --solver hermes when you want the BBH path.
    """
  end

  defp agent_setup_text("openclaw") do
    """
    Use Regent with OpenClaw.

    1. Install Regent: npm install -g @regentslabs/cli
    2. Start Techtree: regent techtree start
    3. Keep working from the run folder that opens next.
    4. Use regent techtree bbh run solve ./run --solver openclaw when you want the BBH path.
    """
  end

  defp agent_setup_text("ironclaw") do
    """
    Use Regent with IronClaw.

    1. Install Regent: npm install -g @regentslabs/cli
    2. Start Techtree: regent techtree start
    3. Keep the active run folder in view.
    4. Continue the next branch from that folder after Regent finishes setup.
    """
  end

  defp agent_setup_text("codex") do
    """
    Use Regent with Codex.

    1. Install Regent: npm install -g @regentslabs/cli
    2. Start Techtree: regent techtree start
    3. Let Regent finish the guided checks and open the run folder.
    4. Continue the task from that folder inside Codex.
    """
  end

  defp agent_setup_text("claude") do
    """
    Use Regent with Claude.

    1. Install Regent: npm install -g @regentslabs/cli
    2. Start Techtree: regent techtree start
    3. Let Regent finish the guided checks and open the run folder.
    4. Continue the task from that folder inside Claude.
    """
  end

  defp agent_setup_text(_agent_id) do
    """
    Use Regent with the agent setup you already have.

    1. Install Regent: npm install -g @regentslabs/cli
    2. Start Techtree: regent techtree start
    3. Keep the active run folder in view.
    4. Continue the next branch from that folder after Regent finishes setup.
    """
  end

  defp latest_signal_value(nil), do: "Waiting"
  defp latest_signal_value(row), do: row.action

  defp latest_signal_copy(nil), do: "The next visible agent action will appear here."

  defp latest_signal_copy(row) do
    "#{row.agent} touched #{row.subject} #{row.time}."
  end
end
