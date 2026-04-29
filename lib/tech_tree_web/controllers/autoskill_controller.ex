defmodule TechTreeWeb.AutoskillController do
  use TechTreeWeb, :controller

  alias TechTree.Autoskill
  alias TechTree.IPFS.LighthouseClient
  alias TechTreeWeb.{ApiError, ControllerHelpers}

  def list_skill_versions(conn, %{"slug" => slug}) do
    versions =
      slug |> Autoskill.list_skill_versions() |> Enum.map(&Autoskill.encode_version_summary/1)

    json(conn, %{data: versions})
  end

  def list_eval_versions(conn, %{"slug" => slug}) do
    versions =
      slug |> Autoskill.list_eval_versions() |> Enum.map(&Autoskill.encode_version_summary/1)

    json(conn, %{data: versions})
  end

  def reviews(conn, %{"id" => id}) do
    case ControllerHelpers.parse_positive_int(id) do
      {:ok, node_id} ->
        json(conn, %{
          data: node_id |> Autoskill.list_reviews() |> Enum.map(&Autoskill.encode_review/1)
        })

      {:error, _reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{code: "invalid_node_id"})
    end
  end

  def listing(conn, %{"id" => id}) do
    case ControllerHelpers.parse_positive_int(id) do
      {:ok, node_id} ->
        case Autoskill.get_listing(node_id) do
          nil -> ApiError.render_halted(conn, :not_found, %{code: "autoskill_listing_not_found"})
          listing -> json(conn, %{data: listing})
        end

      {:error, _reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{code: "invalid_node_id"})
    end
  end

  def bundle(conn, %{"id" => id}) do
    case ControllerHelpers.parse_positive_int(id) do
      {:ok, node_id} ->
        case Autoskill.fetch_bundle_for_access(node_id, %{}) do
          {:ok, bundle} ->
            download_url =
              case bundle.bundle_cid || bundle.encrypted_bundle_cid do
                cid when is_binary(cid) and cid != "" -> LighthouseClient.gateway_url(cid)
                _ -> nil
              end

            json(conn, %{
              data: %{
                node_id: node_id,
                bundle_uri: bundle.bundle_uri || bundle.encrypted_bundle_uri,
                download_url: download_url,
                manifest: bundle.bundle_manifest,
                marimo_entrypoint: bundle.marimo_entrypoint,
                primary_file: bundle.primary_file
              }
            })

          {:error, :payment_required} ->
            ApiError.render_halted(conn, 402, %{code: "autoskill_payment_required"})

          {:error, _reason} ->
            ApiError.render_halted(conn, :unprocessable_entity, %{
              code: "autoskill_bundle_access_failed"
            })
        end

      {:error, _reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{code: "invalid_node_id"})
    end
  end
end
