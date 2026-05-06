defmodule TechTreeWeb.AgentTechController do
  use TechTreeWeb, :controller

  alias TechTree.Tech
  alias TechTreeWeb.{AgentApiResult, ControllerHelpers}

  def prepare_claim(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Tech.prepare_reward_claim(agent, params) do
      {:ok, result} -> json(conn, %{data: result})
      {:error, reason} -> render_error(conn, "tech_claim_prepare_failed", reason)
    end
  end

  def prepare_withdrawal(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Tech.prepare_withdrawal(agent, params) do
      {:ok, result} -> json(conn, %{data: result})
      {:error, reason} -> render_error(conn, "tech_withdraw_prepare_failed", reason)
    end
  end

  def prepare_leaderboard_registration(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Tech.prepare_leaderboard_registration(agent, params) do
      {:ok, result} -> json(conn, %{data: result})
      {:error, reason} -> render_error(conn, "tech_leaderboard_prepare_failed", reason)
    end
  end

  def prepare_reward_root(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Tech.prepare_reward_root(agent, params) do
      {:ok, result} -> json(conn, %{data: result})
      {:error, reason} -> render_error(conn, "tech_reward_root_prepare_failed", reason)
    end
  end

  defp render_error(conn, code, %Ecto.Changeset{} = changeset) do
    AgentApiResult.render_changeset(conn, :unprocessable_entity, code, changeset)
  end

  defp render_error(conn, code, reason) do
    AgentApiResult.render_message(conn, :unprocessable_entity, code, public_reason(reason))
  end

  defp public_reason(:agent_id_mismatch), do: "Use the signed-in agent id for this action."
  defp public_reason(:reward_proof_not_found), do: "No reward proof is available for this claim."
  defp public_reason(:amount_zero), do: "Amount must be greater than zero."
  defp public_reason(:invalid_address), do: "Enter valid recipient addresses."
  defp public_reason(:invalid_leaderboard_kind), do: "Leaderboard kind is not supported."
  defp public_reason(:allocations_required), do: "Reward allocations are required."
  defp public_reason(:invalid_allocation), do: "Reward allocation rows are invalid."
  defp public_reason(_reason), do: "TECH request is invalid."
end
