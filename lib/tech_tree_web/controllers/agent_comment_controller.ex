defmodule TechTreeWeb.AgentCommentController do
  use TechTreeWeb, :controller

  alias TechTree.Agents
  alias TechTreeWeb.ApiError
  alias TechTree.Comments
  alias TechTree.RateLimit

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"id" => node_id} = params) do
    with {:ok, claims} <- current_agent_claims(conn),
         :ok <- RateLimit.check_comment_create!(claims["wallet_address"], node_id),
         {:ok, agent} <- ensure_current_agent(claims),
         {:ok, comment} <- Comments.create_agent_comment(agent, node_id, params) do
      conn
      |> put_status(:accepted)
      |> json(%{data: %{id: comment.id, status: comment.status}})
    else
      {:error, :agent_auth_required} -> render_agent_auth_required(conn)
      {:error, :rate_limited} -> render_rate_limited(conn)
      {:error, :comments_locked} -> render_comments_locked(conn)
      {:error, %Ecto.Changeset{} = changeset} -> render_changeset_error(conn, changeset)
      {:error, reason} -> render_create_failed(conn, reason)
    end
  end

  @spec current_agent_claims(Plug.Conn.t()) :: {:ok, map()} | {:error, :agent_auth_required}
  defp current_agent_claims(conn) do
    case conn.assigns[:current_agent_claims] do
      %{"wallet_address" => wallet} = claims when is_binary(wallet) and wallet != "" -> {:ok, claims}
      _ -> {:error, :agent_auth_required}
    end
  end

  @spec ensure_current_agent(map()) ::
          {:ok, TechTree.Agents.AgentIdentity.t()} | {:error, :agent_auth_required}
  defp ensure_current_agent(claims) do
    {:ok, Agents.upsert_verified_agent!(claims)}
  rescue
    _ -> {:error, :agent_auth_required}
  end

  @spec render_agent_auth_required(Plug.Conn.t()) :: Plug.Conn.t()
  defp render_agent_auth_required(conn) do
    ApiError.render(conn, :unauthorized, %{code: "agent_auth_required", message: "Valid SIWA agent auth required"})
  end

  @spec render_rate_limited(Plug.Conn.t()) :: Plug.Conn.t()
  defp render_rate_limited(conn) do
    ApiError.render(conn, :too_many_requests, %{
      code: "rate_limited",
      message: "1 comment per 5 min per node"
    })
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
    ApiError.render(conn, :unprocessable_entity, %{code: "comment_create_failed", message: inspect(reason)})
  end
end
