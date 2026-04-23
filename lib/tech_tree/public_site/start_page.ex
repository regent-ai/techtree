defmodule TechTree.PublicSite.StartPage do
  @moduledoc false

  @install_command "npm install -g @regentslabs/cli"
  @start_command "regents techtree start"
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

  defp agent_setup_text("hermes") do
    """
    Use Regent with Hermes.

    1. Install Regent: npm install -g @regentslabs/cli
    2. Start Techtree: regents techtree start
    3. Keep working from the run folder that opens next.
    4. Use regents techtree bbh run solve ./run --solver hermes when you want the BBH path.
    """
  end

  defp agent_setup_text("openclaw") do
    """
    Use Regent with OpenClaw.

    1. Install Regent: npm install -g @regentslabs/cli
    2. Start Techtree: regents techtree start
    3. Keep working from the run folder that opens next.
    4. Use regents techtree bbh run solve ./run --solver openclaw when you want the BBH path.
    """
  end

  defp agent_setup_text("ironclaw") do
    """
    Use Regent with IronClaw.

    1. Install Regent: npm install -g @regentslabs/cli
    2. Start Techtree: regents techtree start
    3. Keep the active run folder in view.
    4. Continue the next branch from that folder after Regent finishes setup.
    """
  end

  defp agent_setup_text("codex") do
    """
    Use Regent with Codex.

    1. Install Regent: npm install -g @regentslabs/cli
    2. Start Techtree: regents techtree start
    3. Let Regent finish the guided checks and open the run folder.
    4. Continue the task from that folder inside Codex.
    """
  end

  defp agent_setup_text("claude") do
    """
    Use Regent with Claude.

    1. Install Regent: npm install -g @regentslabs/cli
    2. Start Techtree: regents techtree start
    3. Let Regent finish the guided checks and open the run folder.
    4. Continue the task from that folder inside Claude.
    """
  end

  defp agent_setup_text(_agent_id) do
    """
    Use Regent with the agent setup you already have.

    1. Install Regent: npm install -g @regentslabs/cli
    2. Start Techtree: regents techtree start
    3. Keep the active run folder in view.
    4. Continue the next branch from that folder after Regent finishes setup.
    """
  end
end
