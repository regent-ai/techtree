defmodule TechTree.Nodes.Publishing.Idempotency do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Nodes.Node
  alias TechTree.Repo
  alias TechTree.Nodes.Publishing.Attrs

  def find_existing_node_by_idempotency(_agent_id, nil), do: nil

  def find_existing_node_by_idempotency(agent_id, idempotency_key) do
    Node
    |> where(
      [n],
      n.creator_agent_id == ^agent_id and n.publish_idempotency_key == ^idempotency_key
    )
    |> order_by([n], desc: n.id)
    |> limit(1)
    |> Repo.one()
  end

  def maybe_resolve_idempotent_insert_conflict(agent_id, publish_idempotency_key, changeset) do
    if publish_idempotency_conflict?(changeset) do
      case find_existing_node_by_idempotency(agent_id, publish_idempotency_key) do
        %Node{} = node -> {:ok, node}
        nil -> {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  def publish_idempotency_conflict?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:publish_idempotency_key, {_message, opts}} ->
        opts[:constraint] == :unique

      _ ->
        false
    end)
  end

  def build_publish_idempotency_key(node_id, manifest_hash),
    do: "node:#{node_id}:#{manifest_hash}"

  def build_requested_publish_idempotency_key(agent_id, attrs) do
    Attrs.attr_value(attrs, :publish_idempotency_key) ||
      "node:req:#{agent_id}:#{System.unique_integer([:positive, :monotonic])}"
  end

  def normalize_publish_idempotency_key(node_id, manifest_hash, attrs, existing) do
    Attrs.attr_value(attrs, :publish_idempotency_key) ||
      existing ||
      build_publish_idempotency_key(node_id, manifest_hash || "missing-manifest-hash")
  end
end
