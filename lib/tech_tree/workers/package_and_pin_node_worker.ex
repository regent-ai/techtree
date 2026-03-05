defmodule TechTree.Workers.PackageAndPinNodeWorker do
  @moduledoc false
  use Oban.Worker, queue: :canonical, max_attempts: 20

  require Logger

  alias TechTree.IPFS.NodeBundleBuilder
  alias TechTree.Repo
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Workers.AnchorNodeWorker

  @anchor_unique_period 86_400

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: %{"node_id" => node_id}}) do
    node = Repo.get!(Node, node_id) |> Repo.preload([:tag_edges_out])

    case node.status do
      :ready ->
        :ok

      :pending_chain ->
        if materialized_payload_ready_for_anchor?(node) do
          enqueue_anchor!(node.id, node.manifest_uri, node.manifest_hash)
        else
          Logger.debug("rebuilding missing materialized payload for node_id=#{node.id}")
          bundle = build_and_pin_bundle(node)
          transition_to_pending_chain!(node.id, bundle)
          enqueue_anchor!(node.id, bundle.manifest_uri, bundle.manifest_hash_hex)
        end

      :pending_ipfs ->
        bundle = build_and_pin_bundle(node)
        transition_to_pending_chain!(node.id, bundle)
        enqueue_anchor!(node.id, bundle.manifest_uri, bundle.manifest_hash_hex)

      _ ->
        :ok
    end

    :ok
  rescue
    error -> {:error, error}
  end

  @spec enqueue_anchor!(integer(), String.t() | nil, String.t() | nil) :: :ok
  defp enqueue_anchor!(node_id, manifest_uri, manifest_hash)
       when is_binary(manifest_uri) and byte_size(manifest_uri) > 0 and is_binary(manifest_hash) and
              byte_size(manifest_hash) > 0 do
    {:ok, _job} =
      Oban.insert(
        AnchorNodeWorker.new(
          %{
            "node_id" => node_id,
            "manifest_uri" => manifest_uri,
            "manifest_hash" => manifest_hash
          },
          unique: [period: @anchor_unique_period, keys: [:node_id]]
        )
      )

    :ok
  end

  defp enqueue_anchor!(_node_id, _manifest_uri, _manifest_hash) do
    raise ArgumentError, "missing manifest payload for anchor enqueue"
  end

  @spec build_and_pin_bundle(Node.t()) :: map()
  defp build_and_pin_bundle(node) do
    NodeBundleBuilder.build_and_pin!(
      node,
      %{
        "notebook_source" => node.notebook_source,
        "skill_md_body" => node.skill_md_body,
        "sidelinks" =>
          Enum.map(
            node.tag_edges_out,
            &%{"node_id" => &1.dst_node_id, "tag" => &1.tag, "ordinal" => &1.ordinal}
          )
      }
    )
  end

  @spec transition_to_pending_chain!(integer(), map()) :: :ok
  defp transition_to_pending_chain!(node_id, bundle) do
    _transition_result =
      Nodes.mark_node_pending_chain!(node_id, %{
        manifest_cid: bundle.manifest_cid,
        manifest_uri: bundle.manifest_uri,
        manifest_hash: bundle.manifest_hash_hex,
        notebook_cid: bundle.notebook_cid,
        skill_md_cid: bundle.skill_md_cid,
        skill_md_body: bundle.skill_md_body,
        status: :pending_chain
      })

    :ok
  end

  @spec materialized_payload_ready_for_anchor?(Node.t()) :: boolean()
  defp materialized_payload_ready_for_anchor?(%Node{} = node) do
    has_text?(node.manifest_cid) and
      has_text?(node.manifest_uri) and
      has_text?(node.manifest_hash) and
      has_text?(node.notebook_cid)
  end

  @spec has_text?(String.t() | nil) :: boolean()
  defp has_text?(value) when is_binary(value), do: byte_size(String.trim(value)) > 0
  defp has_text?(_value), do: false
end
