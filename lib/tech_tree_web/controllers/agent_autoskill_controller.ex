defmodule TechTreeWeb.AgentAutoskillController do
  use TechTreeWeb, :controller

  alias TechTree.Autoskill
  alias TechTree.NodeAccess
  alias TechTree.IPFS.LighthouseClient
  alias TechTreeWeb.{AgentApiResult, ApiError, ControllerHelpers}

  def create_skill(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Autoskill.create_skill_version(agent, params) do
      {:ok, %{node: node}} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{node_id: node.id}})

      {:error, %Ecto.Changeset{} = cs} ->
        AgentApiResult.render_changeset(
          conn,
          :unprocessable_entity,
          "autoskill_skill_invalid",
          cs
        )

      {:error, reason} ->
        AgentApiResult.render_reason(
          conn,
          :unprocessable_entity,
          "autoskill_skill_create_failed",
          reason
        )
    end
  end

  def create_eval(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Autoskill.create_eval_version(agent, params) do
      {:ok, %{node: node}} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{node_id: node.id}})

      {:error, %Ecto.Changeset{} = cs} ->
        AgentApiResult.render_changeset(conn, :unprocessable_entity, "autoskill_eval_invalid", cs)

      {:error, reason} ->
        AgentApiResult.render_reason(
          conn,
          :unprocessable_entity,
          "autoskill_eval_create_failed",
          reason
        )
    end
  end

  def create_result(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Autoskill.publish_result(agent, params) do
      {:ok, result} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{result_id: result.id}})

      {:error, %Ecto.Changeset{} = cs} ->
        AgentApiResult.render_changeset(
          conn,
          :unprocessable_entity,
          "autoskill_result_invalid",
          cs
        )

      {:error, reason} ->
        AgentApiResult.render_reason(
          conn,
          :unprocessable_entity,
          "autoskill_result_create_failed",
          reason
        )
    end
  end

  def create_community_review(conn, params) do
    create_review(conn, Map.put(params, "kind", "community"))
  end

  def create_replicable_review(conn, params) do
    create_review(conn, Map.put(params, "kind", "replicable"))
  end

  def create_listing(conn, %{"id" => skill_node_id} = params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Autoskill.create_listing(agent, skill_node_id, params) do
      {:ok, listing} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{listing_id: listing.id, status: listing.status}})

      {:error, :replicable_review_threshold_not_met} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          "code" => "autoskill_listing_threshold_not_met"
        })

      {:error, %Ecto.Changeset{} = cs} ->
        AgentApiResult.render_changeset(
          conn,
          :unprocessable_entity,
          "autoskill_listing_invalid",
          cs
        )

      {:error, reason} ->
        AgentApiResult.render_reason(
          conn,
          :unprocessable_entity,
          "autoskill_listing_create_failed",
          reason
        )
    end
  end

  def bundle(conn, %{"id" => id}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case ControllerHelpers.parse_positive_int(id) do
      {:ok, node_id} ->
        case Autoskill.fetch_bundle_for_agent_access(node_id, agent) do
          {:ok, bundle} ->
            payload =
              case bundle.access_mode do
                :gated_paid ->
                  case NodeAccess.fetch_payload_for_agent(node_id, agent) do
                    {:ok, paid_payload} -> paid_payload
                    _ -> %{}
                  end

                :public_free ->
                  %{}
              end

            download_url =
              cond do
                is_binary(payload[:download_url] || payload["download_url"]) ->
                  payload[:download_url] || payload["download_url"]

                cid = bundle.bundle_cid || bundle.encrypted_bundle_cid ->
                  LighthouseClient.gateway_url(cid)

                true ->
                  nil
              end

            json(conn, %{
              data: %{
                node_id: node_id,
                bundle_uri:
                  bundle.bundle_uri || bundle.encrypted_bundle_uri ||
                    payload[:encrypted_payload_uri] || payload["encrypted_payload_uri"],
                download_url: download_url,
                manifest: bundle.bundle_manifest,
                marimo_entrypoint: bundle.marimo_entrypoint,
                primary_file: bundle.primary_file,
                encryption_meta: payload[:encryption_meta] || payload["encryption_meta"] || %{}
              }
            })

          {:error, :payment_required} ->
            ApiError.render_halted(conn, 402, %{"code" => "autoskill_payment_required"})

          {:error, reason} ->
            AgentApiResult.render_reason(
              conn,
              :unprocessable_entity,
              "autoskill_bundle_access_failed",
              reason
            )
        end

      {:error, _reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{"code" => "invalid_node_id"})
    end
  end

  defp create_review(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Autoskill.create_review(agent, params) do
      {:ok, review} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{review_id: review.id}})

      {:error, %Ecto.Changeset{} = cs} ->
        AgentApiResult.render_changeset(
          conn,
          :unprocessable_entity,
          "autoskill_review_invalid",
          cs
        )

      {:error, reason} ->
        AgentApiResult.render_reason(
          conn,
          :unprocessable_entity,
          "autoskill_review_create_failed",
          reason
        )
    end
  end
end
