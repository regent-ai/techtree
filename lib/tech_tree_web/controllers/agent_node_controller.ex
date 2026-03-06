defmodule TechTreeWeb.AgentNodeController do
  use TechTreeWeb, :controller

  alias TechTreeWeb.ApiError
  alias TechTreeWeb.ControllerHelpers
  alias TechTree.Nodes
  alias TechTree.RateLimit

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    claims = conn.assigns.current_agent_claims
    agent = ControllerHelpers.ensure_current_agent(conn)

    with :ok <- require_notebook_source(params),
         {:ok, normalized_params} <- normalize_parent_id(params) do
      case maybe_existing_from_idempotency(agent, normalized_params) do
        %TechTree.Nodes.Node{} = existing ->
          render_node_created(conn, existing)

        nil ->
          with :ok <- RateLimit.check_node_create!(claims["wallet_address"]),
               {:ok, node} <-
                 Nodes.create_agent_node(agent, normalized_params, skip_idempotency_lookup: true) do
            render_node_created(conn, node)
          else
            {:error, :rate_limited} -> render_rate_limited(conn)
            {:error, :parent_required} -> render_unprocessable(conn, "parent_id_required")
            {:error, :invalid_parent_id} -> render_unprocessable(conn, "invalid_parent_id")
            {:error, :parent_not_found} -> render_unprocessable(conn, "parent_not_found")
            {:error, %Ecto.Changeset{} = changeset} -> render_changeset_error(conn, changeset)
            {:error, reason} -> render_create_failed(conn, reason)
          end
      end
    else
      {:error, :notebook_source_required} -> render_notebook_source_required(conn)
      {:error, :invalid_parent_id} -> render_unprocessable(conn, "invalid_parent_id")
    end
  end

  @spec require_notebook_source(map()) :: :ok | {:error, :notebook_source_required}
  defp require_notebook_source(%{"notebook_source" => notebook_source})
       when is_binary(notebook_source) do
    if String.trim(notebook_source) == "", do: {:error, :notebook_source_required}, else: :ok
  end

  defp require_notebook_source(_params), do: {:error, :notebook_source_required}

  @spec normalize_parent_id(map()) :: {:ok, map()} | {:error, :invalid_parent_id}
  defp normalize_parent_id(params) do
    case ControllerHelpers.fetch_param(params, "parent_id", :parent_id) do
      nil ->
        {:ok, params}

      value ->
        case ControllerHelpers.parse_positive_int(value) do
          {:ok, normalized} -> {:ok, Map.put(params, "parent_id", normalized)}
          {:error, _reason} -> {:error, :invalid_parent_id}
        end
    end
  end

  @spec render_notebook_source_required(Plug.Conn.t()) :: Plug.Conn.t()
  defp render_notebook_source_required(conn) do
    ApiError.render(conn, :unprocessable_entity, %{code: "notebook_source_required"})
  end

  @spec render_rate_limited(Plug.Conn.t()) :: Plug.Conn.t()
  defp render_rate_limited(conn) do
    ApiError.render(conn, :too_many_requests, %{
      code: "rate_limited",
      message: "1 node per hour per agent"
    })
  end

  @spec render_unprocessable(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  defp render_unprocessable(conn, code) do
    ApiError.render(conn, :unprocessable_entity, %{code: code})
  end

  @spec render_changeset_error(Plug.Conn.t(), Ecto.Changeset.t()) :: Plug.Conn.t()
  defp render_changeset_error(conn, changeset) do
    ApiError.render(conn, :unprocessable_entity, %{
      code: "node_create_failed",
      details: ApiError.translate_changeset(changeset)
    })
  end

  @spec render_create_failed(Plug.Conn.t(), term()) :: Plug.Conn.t()
  defp render_create_failed(conn, reason) do
    ApiError.render(conn, :unprocessable_entity, %{
      code: "node_create_failed",
      message: inspect(reason)
    })
  end

  @spec encode_anchor_status(atom() | String.t() | nil) :: String.t()
  defp encode_anchor_status(status) when status in [:anchored, "anchored"], do: "anchored"

  defp encode_anchor_status(status) when status in [:failed_anchor, "failed_anchor"],
    do: "failed_anchor"

  defp encode_anchor_status(_status), do: "pending"

  @spec maybe_existing_from_idempotency(TechTree.Agents.AgentIdentity.t(), map()) ::
          TechTree.Nodes.Node.t() | nil
  defp maybe_existing_from_idempotency(agent, params) do
    params
    |> ControllerHelpers.fetch_param("idempotency_key", :idempotency_key)
    |> ControllerHelpers.normalize_optional_text()
    |> then(&Nodes.get_agent_node_by_idempotency(agent.id, &1))
  end

  @spec render_node_created(Plug.Conn.t(), TechTree.Nodes.Node.t()) :: Plug.Conn.t()
  defp render_node_created(conn, node) do
    conn
    |> put_status(:created)
    |> json(%{
      data: %{
        node_id: node.id,
        artifact_cid: node.manifest_cid,
        status: node.status,
        anchor_status: encode_anchor_status(node.status)
      }
    })
  end
end