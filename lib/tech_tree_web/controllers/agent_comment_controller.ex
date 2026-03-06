defmodule TechTreeWeb.AgentCommentController do
  use TechTreeWeb, :controller

  alias TechTreeWeb.ApiError
  alias TechTreeWeb.ControllerHelpers
  alias TechTree.Comments
  alias TechTree.RateLimit

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    claims = conn.assigns.current_agent_claims
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, node_id} <- parse_node_id(params) do
      case maybe_existing_from_idempotency(agent.id, node_id, params) do
        %TechTree.Comments.Comment{} = existing ->
          render_comment_created(conn, existing)

        nil ->
          with :ok <- RateLimit.check_comment_create!(claims["wallet_address"], node_id),
               {:ok, comment} <-
                 Comments.create_agent_comment(agent, node_id, params,
                   skip_idempotency_lookup: true
                 ) do
            render_comment_created(conn, comment)
          else
            {:error, :rate_limited} -> render_rate_limited(conn)
            {:error, :comments_locked} -> render_comments_locked(conn)
            {:error, :node_not_found} -> render_node_not_found(conn)
            {:error, %Ecto.Changeset{} = changeset} -> render_changeset_error(conn, changeset)
            {:error, reason} -> render_create_failed(conn, reason)
          end
      end
    else
      {:error, :node_id_required} -> render_node_id_required(conn)
      {:error, :invalid_node_id} -> render_invalid_node_id(conn)
    end
  end

  @spec parse_node_id(map()) :: {:ok, integer()} | {:error, :node_id_required | :invalid_node_id}
  defp parse_node_id(params) do
    case ControllerHelpers.parse_positive_int_param(params, "node_id", :node_id) do
      {:ok, node_id} -> {:ok, node_id}
      {:error, :required} -> {:error, :node_id_required}
      {:error, :invalid} -> {:error, :invalid_node_id}
    end
  end

  @spec render_rate_limited(Plug.Conn.t()) :: Plug.Conn.t()
  defp render_rate_limited(conn) do
    ApiError.render(conn, :too_many_requests, %{
      code: "rate_limited",
      message: "1 comment per 5 min per node"
    })
  end

  @spec render_node_id_required(Plug.Conn.t()) :: Plug.Conn.t()
  defp render_node_id_required(conn) do
    ApiError.render(conn, :unprocessable_entity, %{code: "node_id_required"})
  end

  @spec render_invalid_node_id(Plug.Conn.t()) :: Plug.Conn.t()
  defp render_invalid_node_id(conn) do
    ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})
  end

  @spec render_node_not_found(Plug.Conn.t()) :: Plug.Conn.t()
  defp render_node_not_found(conn) do
    ApiError.render(conn, :not_found, %{code: "node_not_found"})
  end

  @spec render_comments_locked(Plug.Conn.t()) :: Plug.Conn.t()
  defp render_comments_locked(conn) do
    ApiError.render(conn, :forbidden, %{
      code: "comments_locked",
      message: "Comments are locked on this node"
    })
  end

  @spec render_changeset_error(Plug.Conn.t(), Ecto.Changeset.t()) :: Plug.Conn.t()
  defp render_changeset_error(conn, changeset) do
    ApiError.render(conn, :unprocessable_entity, %{
      code: "comment_create_failed",
      details: ApiError.translate_changeset(changeset)
    })
  end

  @spec render_create_failed(Plug.Conn.t(), term()) :: Plug.Conn.t()
  defp render_create_failed(conn, reason) do
    ApiError.render(conn, :unprocessable_entity, %{
      code: "comment_create_failed",
      message: inspect(reason)
    })
  end

  @spec maybe_existing_from_idempotency(integer(), integer(), map()) ::
          TechTree.Comments.Comment.t() | nil
  defp maybe_existing_from_idempotency(agent_id, node_id, params) do
    params
    |> ControllerHelpers.fetch_param("idempotency_key", :idempotency_key)
    |> ControllerHelpers.normalize_optional_text()
    |> then(&Comments.get_agent_comment_by_idempotency(agent_id, node_id, &1))
  end

  @spec render_comment_created(Plug.Conn.t(), TechTree.Comments.Comment.t()) :: Plug.Conn.t()
  defp render_comment_created(conn, comment) do
    conn
    |> put_status(:created)
    |> json(%{
      data: %{
        comment_id: comment.id,
        node_id: comment.node_id,
        created_at: comment.inserted_at
      }
    })
  end
end