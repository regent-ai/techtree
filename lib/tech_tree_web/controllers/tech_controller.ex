defmodule TechTreeWeb.TechController do
  use TechTreeWeb, :controller

  alias TechTree.Tech
  alias TechTreeWeb.ApiError

  def status(conn, _params) do
    json(conn, %{data: Tech.status()})
  end

  def current_epoch(conn, _params) do
    json(conn, %{data: Tech.current_epoch() |> Tech.encode_epoch()})
  end

  def leaderboards(conn, params) do
    data =
      params
      |> Tech.list_leaderboards()
      |> Enum.map(&Tech.encode_leaderboard/1)

    json(conn, %{data: data})
  end

  def rewards(conn, params) do
    data =
      params
      |> Tech.list_reward_manifests()
      |> Enum.map(&Tech.encode_manifest/1)

    json(conn, %{data: data})
  end

  def proof(conn, params) do
    case Tech.reward_proof(params) do
      {:ok, proof} ->
        json(conn, %{data: proof})

      {:error, :reward_proof_not_found} ->
        ApiError.render(conn, :not_found, %{
          "code" => "tech_reward_proof_not_found",
          "message" => "No reward proof was found for that agent and epoch."
        })

      {:error, reason} ->
        ApiError.render(conn, :unprocessable_entity, %{
          "code" => "tech_reward_proof_invalid",
          "message" => public_reason(reason)
        })
    end
  end

  defp public_reason(:agent_id_required), do: "Agent id is required."
  defp public_reason(:epoch_required), do: "Epoch is required."
  defp public_reason(:invalid_agent_id), do: "Agent id must be a number."
  defp public_reason(:invalid_integer), do: "Epoch must be a number."
  defp public_reason(:invalid_reward_lane), do: "Reward lane is invalid."
  defp public_reason(_reason), do: "Reward proof request is invalid."
end
