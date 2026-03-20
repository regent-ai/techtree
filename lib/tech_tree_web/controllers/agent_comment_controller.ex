defmodule TechTreeWeb.AgentCommentController do
  use TechTreeWeb, :controller

  alias TechTree.RateLimit
  alias TechTreeWeb.ApiError
  alias TechTreeWeb.ControllerHelpers
  alias TechTree.Comments

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, node_id} <- parse_node_id(params) do
      case maybe_existing_from_idempotency(agent.id, node_id, params) do
        %TechTree.Comments.Comment{} = existing ->
          render_comment_created(conn, existing)

        nil ->
          with :ok <- enforce_create_limit(conn, agent, node_id),
               {:ok, comment} <-
                 Comments.create_agent_comment(agent, node_id, params,
                   skip_idempotency_lookup: true
                 ) do
            render_comment_created(conn, comment)
          else
            {:error, %{retry_after_ms: retry_after_ms}} ->
              render_rate_limit(conn, "comment_create_rate_limited", retry_after_ms)

            {:error, :comments_locked} ->
              render_comments_locked(conn)

            {:error, :node_not_found} ->
              render_node_not_found(conn)

            {:error, %Ecto.Changeset{} = changeset} ->
              render_changeset_error(conn, changeset)

            {:error, reason} ->
              render_create_failed(conn, reason)
          end
      end
    else
      {:error, :node_id_required} -> render_node_id_required(conn)
      {:error, :invalid_node_id} -> render_invalid_node_id(conn)
    end
  end

  defp enforce_create_limit(conn, agent, node_id) do
    node_scope = ":node:#{node_id}"
    ip_scope = ControllerHelpers.client_ip_scope(conn)

    RateLimit.allow_agent_comment_create(
      actor_scope: "agent:#{agent.id}#{node_scope}",
      principal_scope: "wallet:#{agent.wallet_address}#{node_scope}",
      ip_scope: if(is_binary(ip_scope), do: "#{ip_scope}#{node_scope}", else: nil)
    )
  end

  @spec parse_node_id(map()) :: {:ok, integer()} | {:error, :node_id_required | :invalid_node_id}
  defp parse_node_id(params) do
    case ControllerHelpers.parse_positive_int_param(params, "node_id", :node_id) do
      {:ok, node_id} -> {:ok, node_id}
      {:error, :required} -> {:error, :node_id_required}
      {:error, :invalid} -> {:error, :invalid_node_id}
    end
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

  @spec render_rate_limit(Plug.Conn.t(), String.t(), pos_integer()) :: Plug.Conn.t()
  defp render_rate_limit(conn, code, retry_after_ms) do
    retry_after_seconds = retry_after_ms |> Kernel./(1_000) |> Float.ceil() |> trunc()

    conn
    |> put_resp_header("retry-after", Integer.to_string(max(retry_after_seconds, 1)))
    |> ApiError.render(:too_many_requests, %{
      code: code,
      retry_after_ms: retry_after_ms
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
