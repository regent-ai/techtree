defmodule TechTree.IPFS.NodeBundleBuilder do
  @moduledoc false

  alias TechTree.IPFS.{Digests, LighthouseClient, NodeManifest}
  alias TechTree.Repo
  alias TechTree.Nodes.Node

  @spec build_and_pin!(Node.t(), map(), keyword()) :: map()
  def build_and_pin!(%Node{} = node, payload, opts \\ []) do
    node = Repo.preload(node, [:creator_agent, :tag_edges_out])

    notebook_source =
      payload["notebook_source"] || payload[:notebook_source] || node.notebook_source ||
        raise(ArgumentError, "missing notebook_source")

    skill_md_body = payload["skill_md_body"] || payload[:skill_md_body] || node.skill_md_body

    sidelinks =
      payload["sidelinks"] || payload[:sidelinks] ||
        Enum.map(node.tag_edges_out, fn edge ->
          %{"node_id" => edge.dst_node_id, "tag" => edge.tag, "ordinal" => edge.ordinal}
        end)

    notebook_sha256 = Digests.sha256_hex(notebook_source)

    notebook_upload =
      LighthouseClient.upload_content!(
        "notebook.py",
        notebook_source,
        content_type: "text/x-python",
        storage_type: opts[:storage_type]
      )

    {skill_md_cid, skill_md_sha256} =
      case normalized_skill_md_body(node, skill_md_body) do
        nil ->
          {nil, nil}

        body ->
          upload =
            LighthouseClient.upload_content!(
              "skill.md",
              body,
              content_type: "text/markdown",
              storage_type: opts[:storage_type]
            )

          {upload.cid, Digests.sha256_hex(body)}
      end

    manifest_json =
      NodeManifest.render!(
        node,
        %{
          notebook_cid: notebook_upload.cid,
          skill_md_cid: skill_md_cid,
          notebook_sha256: notebook_sha256,
          skill_md_sha256: skill_md_sha256
        },
        sidelinks: sidelinks
      )

    manifest_hash_bin = Digests.sha256(manifest_json)
    manifest_hash_hex = Base.encode16(manifest_hash_bin, case: :lower)

    manifest_upload =
      LighthouseClient.upload_content!(
        "manifest.json",
        manifest_json,
        content_type: "application/json",
        storage_type: opts[:storage_type]
      )

    %{
      manifest_cid: manifest_upload.cid,
      manifest_hash_bin: manifest_hash_bin,
      manifest_hash_hex: manifest_hash_hex,
      manifest_uri: "ipfs://#{manifest_upload.cid}",
      notebook_cid: notebook_upload.cid,
      skill_md_cid: skill_md_cid,
      skill_md_body: normalized_skill_md_body(node, skill_md_body)
    }
  end

  @spec normalized_skill_md_body(Node.t(), String.t() | nil) :: String.t() | nil
  defp normalized_skill_md_body(%Node{kind: :skill}, body) when is_binary(body) and byte_size(body) > 0,
    do: body

  defp normalized_skill_md_body(%Node{kind: :skill}, _body),
    do: raise(ArgumentError, "skill node requires non-empty skill_md_body")

  defp normalized_skill_md_body(_node, body) when is_binary(body) and byte_size(body) > 0,
    do: body

  defp normalized_skill_md_body(_node, _body), do: nil
end
