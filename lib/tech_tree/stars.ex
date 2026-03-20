defmodule TechTree.Stars do
  @moduledoc false

  import Ecto.Query
  import TechTree.QueryHelpers

  alias TechTree.Activity
  alias TechTree.Nodes.Node
  alias TechTree.Repo
  alias TechTree.Stars.NodeStar

  @spec star_agent(integer() | String.t(), integer()) ::
          {:ok, NodeStar.t()} | {:error, :node_not_found | Ecto.Changeset.t()}
  def star_agent(node_id, agent_id) do
    create_star(node_id, :agent, agent_id)
  end

  @spec unstar_agent(integer() | String.t(), integer()) :: :ok | {:error, :node_not_found}
  def unstar_agent(node_id, agent_id) do
    delete_star(node_id, :agent, agent_id)
  end

  @spec create_star(integer() | String.t(), atom(), integer()) ::
          {:ok, NodeStar.t()} | {:error, :node_not_found | Ecto.Changeset.t()}
  defp create_star(node_id, actor_type, actor_ref) do
    normalized_node_id = normalize_id(node_id)

    case Repo.get(Node, normalized_node_id) do
      nil ->
        {:error, :node_not_found}

      %Node{} ->
        Repo.transaction(fn ->
          inserted_star =
            %NodeStar{}
            |> NodeStar.changeset(%{
              node_id: normalized_node_id,
              actor_type: actor_type,
              actor_ref: actor_ref
            })
            |> Repo.insert(
              on_conflict: :nothing,
              conflict_target: {:unsafe_fragment, "(node_id, actor_type, actor_ref)"}
            )

          star =
            case inserted_star do
              {:ok, %NodeStar{id: nil}} ->
                fetch_star!(normalized_node_id, actor_type, actor_ref)

              {:ok, %NodeStar{} = star} ->
                _ = log_starred_once(star)
                star

              {:error, %Ecto.Changeset{} = changeset} ->
                Repo.rollback(changeset)
            end

          star
        end)
        |> case do
          {:ok, %NodeStar{} = star} -> {:ok, star}
          {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
        end
    end
  end

  @spec delete_star(integer() | String.t(), atom(), integer()) :: :ok | {:error, :node_not_found}
  defp delete_star(node_id, actor_type, actor_ref) do
    normalized_node_id = normalize_id(node_id)

    case Repo.get(Node, normalized_node_id) do
      nil ->
        {:error, :node_not_found}

      %Node{} ->
        Repo.transaction(fn ->
          {deleted_count, _rows} =
            NodeStar
            |> where([s], s.node_id == ^normalized_node_id)
            |> where([s], s.actor_type == ^actor_type)
            |> where([s], s.actor_ref == ^actor_ref)
            |> Repo.delete_all()

          if deleted_count > 0 do
            Activity.log!("node.unstarred", actor_type, actor_ref, normalized_node_id, %{})
          end

          :ok
        end)

        :ok
    end
  end

  @spec log_starred_once(NodeStar.t()) :: :ok
  defp log_starred_once(%NodeStar{} = star) do
    Activity.log!("node.starred", star.actor_type, star.actor_ref, star.node_id, %{})
    :ok
  end

  @spec fetch_star!(integer(), atom(), integer()) :: NodeStar.t()
  defp fetch_star!(node_id, actor_type, actor_ref) do
    NodeStar
    |> where([s], s.node_id == ^node_id)
    |> where([s], s.actor_type == ^actor_type)
    |> where([s], s.actor_ref == ^actor_ref)
    |> limit(1)
    |> Repo.one!()
  end
end
