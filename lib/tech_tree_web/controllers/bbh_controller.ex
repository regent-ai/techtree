defmodule TechTreeWeb.BbhController do
  use TechTreeWeb, :controller

  alias TechTree.BBH
  alias TechTreeWeb.ApiError

  def leaderboard(conn, params) do
    json(conn, %{data: BBH.leaderboard(params)})
  end

  def genome(conn, %{"id" => genome_id}) do
    case BBH.get_genome(genome_id) do
      nil ->
        ApiError.render_halted(conn, :not_found, %{
          code: "bbh_genome_not_found",
          message: "BBH genome not found"
        })

      genome ->
        json(conn, %{data: present(genome)})
    end
  end

  def run(conn, %{"id" => run_id}) do
    case BBH.get_run(run_id) do
      nil ->
        ApiError.render_halted(conn, :not_found, %{
          code: "bbh_run_not_found",
          message: "BBH run not found"
        })

      run ->
        json(conn, %{data: present(run)})
    end
  end

  def validations(conn, %{"id" => run_id}) do
    json(conn, %{data: present(BBH.list_validations(run_id))})
  end

  defp present(value) when is_list(value), do: Enum.map(value, &present/1)

  defp present(%Ecto.Association.NotLoaded{}), do: nil
  defp present(%DateTime{} = value), do: value
  defp present(%NaiveDateTime{} = value), do: value
  defp present(%Date{} = value), do: value
  defp present(%Time{} = value), do: value

  defp present(%_{} = value) do
    value
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Enum.reduce(%{}, fn {key, nested}, acc ->
      case nested do
        %Ecto.Association.NotLoaded{} ->
          acc

        _ ->
          Map.put(acc, key, present(nested))
      end
    end)
  end

  defp present(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {key, present(nested)} end)
  end

  defp present(value), do: value
end
