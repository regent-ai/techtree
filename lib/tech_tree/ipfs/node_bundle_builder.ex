defmodule TechTree.IPFS.NodeBundleBuilder do
  @moduledoc false

  import Ecto.Query

  alias TechTree.IPFS.{Digests, LighthouseClient, NodeManifest}
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  @spec build_and_pin!(Node.t(), map(), keyword()) :: map()
  def build_and_pin!(%Node{} = node, payload, opts \\ []) do
    upload_fun = opts[:upload_fun] || (&LighthouseClient.upload_content!/3)

    notebook_source =
      payload["notebook_source"] || payload[:notebook_source] || node.notebook_source ||
        raise(ArgumentError, "missing notebook_source")

    skill_md_body = payload["skill_md_body"] || payload[:skill_md_body] || node.skill_md_body
    normalized_skill_md_body = normalized_skill_md_body(skill_md_body, node)

    notebook_upload =
      upload_fun.(
        "notebook.py",
        notebook_source,
        content_type: "text/x-python",
        storage_type: opts[:storage_type]
      )

    notebook_cid = require_valid_cid!(notebook_upload.cid, "notebook.py")

    {skill_md_cid, normalized_skill_md_body} =
      case normalized_skill_md_body do
        nil ->
          {nil, nil}

        body ->
          upload =
            upload_fun.(
              "skill.md",
              body,
              content_type: "text/markdown",
              storage_type: opts[:storage_type]
            )

          {require_valid_cid!(upload.cid, "skill.md"), body}
      end

    parent_cid = payload["parent_cid"] || payload[:parent_cid] || fetch_parent_cid(node.parent_id)

    manifest_json =
      NodeManifest.render!(node, %{
        notebook_cid: notebook_cid,
        skill_cid: skill_md_cid,
        parent_cid: parent_cid
      })

    manifest_hash_hex = Digests.sha256_hex(manifest_json)

    manifest_upload =
      upload_fun.(
        "manifest.json",
        manifest_json,
        content_type: "application/json",
        storage_type: opts[:storage_type]
      )

    manifest_cid = require_valid_cid!(manifest_upload.cid, "manifest.json")

    %{
      manifest_cid: manifest_cid,
      manifest_hash_hex: manifest_hash_hex,
      manifest_uri: "ipfs://#{manifest_cid}",
      notebook_cid: notebook_cid,
      skill_md_cid: skill_md_cid,
      skill_md_body: normalized_skill_md_body
    }
  end

  @spec normalized_skill_md_body(String.t() | nil, Node.t()) :: String.t() | nil
  defp normalized_skill_md_body(body, %Node{kind: :skill}) when is_binary(body) do
    if byte_size(String.trim(body)) > 0 do
      body
    else
      raise(ArgumentError, "skill node requires non-empty skill_md_body")
    end
  end

  defp normalized_skill_md_body(_body, %Node{kind: :skill}),
    do: raise(ArgumentError, "skill node requires non-empty skill_md_body")

  defp normalized_skill_md_body(body, _node) when is_binary(body) do
    if byte_size(String.trim(body)) > 0, do: body, else: nil
  end

  defp normalized_skill_md_body(_body, _node), do: nil

  @spec fetch_parent_cid(integer() | nil) :: String.t() | nil
  defp fetch_parent_cid(nil), do: nil

  defp fetch_parent_cid(parent_id) when is_integer(parent_id) do
    Node
    |> where([n], n.id == ^parent_id)
    |> select([n], n.manifest_cid)
    |> Repo.one()
  end

  @spec require_valid_cid!(String.t() | nil, String.t()) :: String.t()
  defp require_valid_cid!(cid, artifact_name) do
    if LighthouseClient.valid_cid?(cid) do
      cid
    else
      raise(ArgumentError, "upload for #{artifact_name} returned invalid cid: #{inspect(cid)}")
    end
  end
end