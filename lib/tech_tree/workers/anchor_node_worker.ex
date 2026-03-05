defmodule TechTree.Workers.AnchorNodeWorker do
  @moduledoc false
  use Oban.Worker, queue: :chain, max_attempts: 20

  alias TechTree.Base
  alias TechTree.Repo
  alias TechTree.Nodes.Node
  alias TechTree.Workers.AwaitNodeReceiptWorker

  @await_unique_period 86_400

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{
        args: %{
          "node_id" => node_id,
          "manifest_uri" => manifest_uri,
          "manifest_hash" => manifest_hash
        }
      }) do
    node = Repo.get!(Node, node_id) |> Repo.preload(:creator_agent)

    case node.status do
      :ready ->
        :ok

      :pending_chain ->
        verify_manifest_payload!(node, manifest_uri, manifest_hash)

        tx_hash =
          case node.tx_hash do
            existing when is_binary(existing) and byte_size(existing) > 0 ->
              existing

            _ ->
              {:ok, created_tx_hash} =
                Base.create_node(%{
                  node_id: node.id,
                  parent_id: node.parent_id || 0,
                  creator: node.creator_agent.wallet_address,
                  manifest_uri: manifest_uri,
                  manifest_hash: manifest_hash,
                  kind: node_kind_to_uint8(node.kind)
                })

              node
              |> Ecto.Changeset.change(tx_hash: created_tx_hash)
              |> Repo.update!()

              created_tx_hash
          end

        {:ok, _job} =
          Oban.insert(
            AwaitNodeReceiptWorker.new(
              %{
                "node_id" => node.id,
                "tx_hash" => tx_hash,
                "manifest_uri" => manifest_uri,
                "manifest_hash" => manifest_hash
              },
              unique: [period: @await_unique_period, keys: [:node_id]]
            )
          )

        :ok

      _ ->
        raise ArgumentError, "cannot anchor node #{node.id} while status is #{node.status}"
    end

    :ok
  rescue
    error -> {:error, error}
  end

  @spec node_kind_to_uint8(atom()) :: 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7
  defp node_kind_to_uint8(:hypothesis), do: 0
  defp node_kind_to_uint8(:data), do: 1
  defp node_kind_to_uint8(:result), do: 2
  defp node_kind_to_uint8(:null_result), do: 3
  defp node_kind_to_uint8(:review), do: 4
  defp node_kind_to_uint8(:synthesis), do: 5
  defp node_kind_to_uint8(:meta), do: 6
  defp node_kind_to_uint8(:skill), do: 7

  @spec verify_manifest_payload!(Node.t(), String.t(), String.t()) :: :ok
  defp verify_manifest_payload!(%Node{} = node, manifest_uri, manifest_hash) do
    if node.manifest_uri != manifest_uri do
      raise ArgumentError, "manifest_uri mismatch for node #{node.id}"
    end

    if node.manifest_hash != manifest_hash do
      raise ArgumentError, "manifest_hash mismatch for node #{node.id}"
    end

    :ok
  end
end