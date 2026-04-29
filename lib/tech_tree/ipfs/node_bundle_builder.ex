defmodule TechTree.IPFS.NodeBundleBuilder do
  @moduledoc false

  import Ecto.Query

  alias TechTree.IPFS.{Digests, LighthouseClient, NodeManifest}
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  @spec build_and_pin(Node.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def build_and_pin(%Node{} = node, payload, opts \\ []) do
    upload_fun = opts[:upload_fun] || (&LighthouseClient.upload_content/3)

    with {:ok, notebook_source} <- fetch_notebook_source(node, payload),
         {:ok, normalized_skill_md_body} <- normalized_skill_md_body(payload, node),
         {:ok, notebook_upload} <-
           upload_content(
             upload_fun,
             "notebook.py",
             notebook_source,
             content_type: "text/x-python",
             storage_type: opts[:storage_type]
           ),
         {:ok, notebook_cid} <- require_valid_cid(notebook_upload.cid),
         {:ok, skill_md_cid, normalized_skill_md_body} <-
           maybe_upload_skill_md(upload_fun, normalized_skill_md_body, opts),
         parent_cid <-
           payload["parent_cid"] || payload[:parent_cid] || fetch_parent_cid(node.parent_id),
         manifest_json <-
           NodeManifest.render!(node, %{
             notebook_cid: notebook_cid,
             skill_cid: skill_md_cid,
             parent_cid: parent_cid
           }),
         manifest_hash_hex <- Digests.sha256_hex(manifest_json),
         {:ok, manifest_upload} <-
           upload_content(
             upload_fun,
             "manifest.json",
             manifest_json,
             content_type: "application/json",
             storage_type: opts[:storage_type]
           ),
         {:ok, manifest_cid} <- require_valid_cid(manifest_upload.cid) do
      {:ok,
       %{
         manifest_cid: manifest_cid,
         manifest_hash_hex: manifest_hash_hex,
         manifest_uri: "ipfs://#{manifest_cid}",
         notebook_cid: notebook_cid,
         skill_md_cid: skill_md_cid,
         skill_md_body: normalized_skill_md_body
       }}
    end
  rescue
    error -> {:error, error}
  end

  @spec fetch_notebook_source(Node.t(), map()) ::
          {:ok, String.t()} | {:error, :missing_notebook_source}
  defp fetch_notebook_source(node, payload) do
    notebook_source =
      payload["notebook_source"] || payload[:notebook_source] || node.notebook_source ||
        nil

    if is_binary(notebook_source),
      do: {:ok, notebook_source},
      else: {:error, :missing_notebook_source}
  end

  @spec normalized_skill_md_body(map(), Node.t()) :: {:ok, String.t() | nil} | {:error, term()}
  defp normalized_skill_md_body(payload, node) do
    body = payload["skill_md_body"] || payload[:skill_md_body] || node.skill_md_body
    normalize_skill_md_body(body, node)
  end

  defp normalize_skill_md_body(body, %Node{kind: :skill}) when is_binary(body) do
    if byte_size(String.trim(body)) > 0 do
      {:ok, body}
    else
      {:error, :skill_md_body_required}
    end
  end

  defp normalize_skill_md_body(_body, %Node{kind: :skill}),
    do: {:error, :skill_md_body_required}

  defp normalize_skill_md_body(body, _node) when is_binary(body) do
    {:ok, if(byte_size(String.trim(body)) > 0, do: body, else: nil)}
  end

  defp normalize_skill_md_body(_body, _node), do: {:ok, nil}

  @spec fetch_parent_cid(integer() | nil) :: String.t() | nil
  defp fetch_parent_cid(nil), do: nil

  defp fetch_parent_cid(parent_id) when is_integer(parent_id) do
    Node
    |> where([n], n.id == ^parent_id)
    |> select([n], n.manifest_cid)
    |> Repo.one()
  end

  defp maybe_upload_skill_md(_upload_fun, nil, _opts), do: {:ok, nil, nil}

  defp maybe_upload_skill_md(upload_fun, body, opts) do
    with {:ok, upload} <-
           upload_content(
             upload_fun,
             "skill.md",
             body,
             content_type: "text/markdown",
             storage_type: opts[:storage_type]
           ),
         {:ok, cid} <- require_valid_cid(upload.cid) do
      {:ok, cid, body}
    end
  end

  @spec require_valid_cid(String.t() | nil) :: {:ok, String.t()} | {:error, :invalid_cid}
  defp require_valid_cid(cid) do
    if LighthouseClient.valid_cid?(cid) do
      {:ok, cid}
    else
      {:error, :invalid_cid}
    end
  end

  defp upload_content(upload_fun, filename, content, opts) do
    case upload_fun.(filename, content, opts) do
      {:ok, upload} -> {:ok, upload}
      %LighthouseClient.UploadResult{} = upload -> {:ok, upload}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_upload_result, other}}
    end
  rescue
    error -> {:error, error}
  end
end
