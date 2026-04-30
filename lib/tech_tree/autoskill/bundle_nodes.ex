defmodule TechTree.Autoskill.BundleNodes do
  @moduledoc false

  alias TechTree.Autoskill.Listings
  alias TechTree.Autoskill.NodeBundle
  alias TechTree.IPFS.{Digests, LighthouseClient}
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  def resolve_parent_id(kind, attrs) do
    seed = seed_for(kind)

    case attrs["parent_id"] do
      nil ->
        {:ok, Nodes.create_seed_root!(seed, seed).id}

      parent_id ->
        normalized = Listings.normalize_id(parent_id)

        case Repo.get(Node, normalized) do
          %Node{seed: ^seed} -> {:ok, normalized}
          %Node{} -> {:error, :invalid_autoskill_parent}
          nil -> {:error, :parent_not_found}
        end
    end
  end

  def build_node_attrs(:skill, attrs, parent_id) do
    skill_slug = required_text(attrs, "skill_slug")
    skill_version = required_text(attrs, "skill_version")
    title = required_text(attrs, "title")
    summary = optional_text(attrs, "summary")
    preview_md = optional_text(attrs, "preview_md") || "# Preview only"

    with {:ok, skill_slug} <- require_value(skill_slug, :skill_slug_required),
         {:ok, skill_version} <- require_value(skill_version, :skill_version_required),
         {:ok, title} <- require_value(title, :title_required) do
      {:ok,
       %{
         "seed" => "Skills",
         "kind" => "skill",
         "parent_id" => parent_id,
         "title" => title,
         "summary" => summary,
         "slug" => optional_text(attrs, "slug") || skill_slug,
         "skill_slug" => skill_slug,
         "skill_version" => skill_version,
         "notebook_source" =>
           optional_text(attrs, "notebook_source") || preview_notebook(title, preview_md),
         "skill_md_body" => preview_md
       }}
    end
  end

  def build_node_attrs(:eval, attrs, parent_id) do
    title = required_text(attrs, "title")
    slug = required_text(attrs, "slug")

    with {:ok, title} <- require_value(title, :title_required),
         {:ok, slug} <- require_value(slug, :slug_required) do
      {:ok,
       %{
         "seed" => "Evals",
         "kind" => "eval",
         "parent_id" => parent_id,
         "title" => title,
         "summary" => optional_text(attrs, "summary"),
         "slug" => slug,
         "notebook_source" =>
           optional_text(attrs, "notebook_source") ||
             preview_notebook(title, optional_text(attrs, "preview_md"))
       }}
    end
  end

  def create_bundle(node, kind, attrs) do
    uploaded_bundle_attrs = maybe_upload_bundle_archive(attrs)

    %NodeBundle{}
    |> NodeBundle.changeset(%{
      node_id: node.id,
      bundle_type: kind,
      access_mode: attrs["access_mode"],
      preview_md: optional_text(attrs, "preview_md"),
      bundle_manifest: attrs["bundle_manifest"],
      primary_file: optional_text(attrs, "primary_file"),
      marimo_entrypoint: attrs["marimo_entrypoint"],
      bundle_uri:
        Map.get(uploaded_bundle_attrs, :bundle_uri) || optional_text(attrs, "bundle_uri"),
      bundle_cid:
        Map.get(uploaded_bundle_attrs, :bundle_cid) || optional_text(attrs, "bundle_cid"),
      bundle_hash:
        Map.get(uploaded_bundle_attrs, :bundle_hash) || optional_text(attrs, "bundle_hash"),
      encrypted_bundle_uri:
        Map.get(uploaded_bundle_attrs, :encrypted_bundle_uri) ||
          optional_text(attrs, "encrypted_bundle_uri"),
      encrypted_bundle_cid:
        Map.get(uploaded_bundle_attrs, :encrypted_bundle_cid) ||
          optional_text(attrs, "encrypted_bundle_cid"),
      encryption_meta: attrs["encryption_meta"],
      payment_rail: attrs["payment_rail"],
      access_policy: attrs["access_policy"]
    })
    |> Repo.insert()
  end

  def preview_notebook(title, preview_md) do
    """
    import marimo as mo
    app = mo.App()

    @app.cell
    def _():
        title = #{inspect(title)}
        preview = #{inspect(preview_md || "")}
        return title, preview

    if __name__ == "__main__":
        app.run()
    """
  end

  def required_text(attrs, key), do: optional_text(attrs, key)

  def optional_text(attrs, key) do
    case Map.get(attrs, to_string(key)) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  def maybe_upload_bundle_archive(attrs) do
    access_mode = attrs["access_mode"]

    case access_mode do
      "public_free" ->
        archive_upload_attrs(
          attrs["bundle_archive_b64"],
          "autoskill-bundle.json"
        )

      "gated_paid" ->
        archive_upload_attrs(
          attrs["encrypted_bundle_archive_b64"],
          "autoskill-bundle.encrypted.json"
        )

      _ ->
        %{}
    end
  end

  def seed_for(:skill), do: "Skills"
  def seed_for(:eval), do: "Evals"

  defp require_value(nil, error), do: {:error, error}
  defp require_value(value, _error), do: {:ok, value}

  defp archive_upload_attrs(nil, _filename), do: %{}

  defp archive_upload_attrs(encoded_archive, filename) when is_binary(encoded_archive) do
    archive_bytes = Base.decode64!(encoded_archive)

    case LighthouseClient.upload_content(filename, archive_bytes,
           content_type: "application/json"
         ) do
      {:ok, upload} ->
        attrs = %{
          bundle_hash: Digests.sha256_hex(archive_bytes)
        }

        if String.contains?(filename, ".encrypted.") do
          Map.merge(attrs, %{
            encrypted_bundle_uri: "ipfs://#{upload.cid}",
            encrypted_bundle_cid: upload.cid
          })
        else
          Map.merge(attrs, %{
            bundle_uri: "ipfs://#{upload.cid}",
            bundle_cid: upload.cid
          })
        end

      {:error, reason} ->
        raise RuntimeError, "autoskill archive upload failed: #{inspect(reason)}"
    end
  end
end
