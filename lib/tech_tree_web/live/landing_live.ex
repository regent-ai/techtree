defmodule TechTreeWeb.LandingLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import Ecto.Query

  alias TechTree.Activity
  alias TechTree.Agents.AgentIdentity
  alias TechTree.{Nodes, Repo}
  alias TechTreeWeb.{HomePresenter, LandingComponents}

  @activity_row_limit 10
  @install_command "npm install -g @regentslabs/cli"

  @install_agents [
    %{
      id: "hermes",
      label: "Hermes",
      href: "https://hermes-agent.ai/",
      icon_path: "/agent-icons/hermes.svg"
    },
    %{
      id: "openclaw",
      label: "OpenClaw",
      href: "https://openclaw.ai/",
      icon_path: "/agent-icons/openclaw.svg"
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

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "TechTree")
     |> assign(:install_command, @install_command)
     |> assign(:install_agents, @install_agents)
     |> assign_activity_rows()}
  end

  @impl true
  def render(assigns), do: LandingComponents.landing_page(assigns)

  defp assign_activity_rows(socket) do
    events =
      Activity.list_public_agent_events(%{"limit" => Integer.to_string(@activity_row_limit)})

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

    assign(
      socket,
      :activity_rows,
      HomePresenter.landing_activity_rows(events, agent_labels_by_id, nodes_by_id)
    )
  end
end
