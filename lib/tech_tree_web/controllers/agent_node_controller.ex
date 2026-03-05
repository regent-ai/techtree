defmodule TechTreeWeb.AgentNodeController do
  use TechTreeWeb, :controller

  alias TechTree.Agents
  alias TechTreeWeb.ApiError
  alias TechTreeWeb.PublicEncoding
  alias TechTree.Nodes
  alias TechTree.RateLimit
  alias TechTree.Watches

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    with {:ok, claims} <- current_agent_claims(conn),
         :ok <- require_notebook_source(params),
         :ok <- RateLimit.check_node_create!(claims["wallet_address"]),
         {:ok, agent} <- ensure_current_agent(claims),
         {:ok, node} <- Nodes.create_agent_node(agent, params) do
      conn
      |> put_status(:accepted)
      |> json(%{data: %{id: node.id, status: node.status}})
    else
      {:error, :agent_auth_required} -> render_agent_auth_required(conn)
      {:error, :notebook_source_required} -> render_notebook_source_required(conn)
      {:error, :rate_limited} -> render_rate_limited(conn)
      {:error, :parent_required} -> render_unprocessable(conn, "parent_id_required")
      {:error, :parent_not_found} -> render_unprocessable(conn, "parent_not_found")
      {:error, %Ecto.Changeset{} = changeset} -> render_changeset_error(conn, changeset)
      {:error, reason} -> render_create_failed(conn, reason)
    end
  end

  @spec watch(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def watch(conn, %{"id" => node_id}) do
    with {:ok, agent} <- current_agent(conn),
         {:ok, watch} <- Watches.watch_agent(node_id, agent.id) do
      json(conn, %{data: PublicEncoding.encode_watch(watch)})
    else
      {:error, :agent_auth_required} -> render_agent_auth_required(conn)
      {:error, reason} -> render_create_failed(conn, reason)
    end
  end

  @spec unwatch(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def unwatch(conn, %{"id" => node_id}) do
    with {:ok, agent} <- current_agent(conn),
         :ok <- Watches.unwatch_agent(node_id, agent.id) do
      json(conn, %{ok: true})
    else
      {:error, :agent_auth_required} -> render_agent_auth_required(conn)
      {:error, reason} -> render_create_failed(conn, reason)
    end
  end

  @spec require_notebook_source(map()) :: :ok | {:error, :notebook_source_required}
  defp require_notebook_source(%{"notebook_source" => notebook_source})
       when is_binary(notebook_source) do
    if String.trim(notebook_source) == "", do: {:error, :notebook_source_required}, else: :ok
  end

  defp require_notebook_source(_params), do: {:error, :notebook_source_required}

  @spec current_agent_claims(Plug.Conn.t()) :: {:ok, map()} | {:error, :agent_auth_required}
  defp current_agent_claims(conn) do
    case conn.assigns[:current_agent_claims] do
      %{"wallet_address" => wallet} = claims when is_binary(wallet) and wallet != "" -> {:ok, claims}
      _ -> {:error, :agent_auth_required}
    end
  end

  @spec current_agent(Plug.Conn.t()) ::
          {:ok, TechTree.Agents.AgentIdentity.t()} | {:error, :agent_auth_required}
  defp current_agent(conn) do
    with {:ok, claims} <- current_agent_claims(conn),
         {:ok, agent} <- ensure_current_agent(claims) do
      {:ok, agent}
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
    ApiError.render(conn, :unprocessable_entity, %{code: "node_create_failed", message: inspect(reason)})
  end
end
