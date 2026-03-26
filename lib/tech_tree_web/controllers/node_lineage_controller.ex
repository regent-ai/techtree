defmodule TechTreeWeb.NodeLineageController do
  use TechTreeWeb, :controller

  alias TechTree.Nodes
  alias TechTree.Nodes.Lineage
  alias TechTreeWeb.{ApiError, ControllerHelpers}

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    with {:ok, node_id} <- parse_node_id(id),
         {:ok, node} <- fetch_public_node(node_id) do
      json(conn, %{data: Nodes.cross_chain_lineage(node)})
    else
      {:error, :invalid_node_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})

      :error ->
        ApiError.render(conn, :not_found, %{code: "node_not_found"})
    end
  end

  @spec show_private(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show_private(conn, %{"id" => id}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, node_id} <- parse_node_id(id),
         {:ok, node} <- fetch_readable_node(agent.id, node_id) do
      json(conn, %{data: Nodes.cross_chain_lineage(node)})
    else
      {:error, :invalid_node_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})

      :error ->
        ApiError.render(conn, :not_found, %{code: "node_not_found"})
    end
  end

  @spec list_claims(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list_claims(conn, %{"id" => id}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, node_id} <- parse_node_id(id),
         {:ok, node} <- fetch_readable_node(agent.id, node_id) do
      data =
        node
        |> Nodes.list_node_lineage_claims()
        |> Enum.map(&Lineage.encode_claim_history/1)

      json(conn, %{data: data})
    else
      {:error, :invalid_node_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})

      :error ->
        ApiError.render(conn, :not_found, %{code: "node_not_found"})
    end
  end

  @spec create_claim(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_claim(conn, %{"id" => id} = params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, node_id} <- parse_node_id(id),
         {:ok, node} <- fetch_readable_node(agent.id, node_id),
         {:ok, claim} <- Nodes.create_node_lineage_claim(node, agent, params) do
      conn
      |> put_status(:created)
      |> json(%{data: Lineage.encode_claim_history(claim)})
    else
      {:error, :invalid_node_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})

      {:error, {:required, field}} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "#{field}_required"})

      {:error, :invalid_payload} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_lineage_payload"})

      {:error, :invalid_relation} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_lineage_relation"})

      {:error, :invalid_target_chain_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_target_chain_id"})

      {:error, :target_node_not_found} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "target_node_not_found"})

      {:error, :target_node_chain_unavailable} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "target_node_chain_unavailable"})

      {:error, :target_chain_mismatch} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "target_chain_mismatch"})

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "lineage_claim_create_failed",
          details: ApiError.translate_changeset(changeset)
        })

      :error ->
        ApiError.render(conn, :not_found, %{code: "node_not_found"})
    end
  end

  @spec withdraw_claim(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def withdraw_claim(conn, %{"id" => id, "claim_id" => claim_id}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, node_id} <- parse_node_id(id),
         {:ok, parsed_claim_id} <- parse_node_id(claim_id),
         {:ok, node} <- fetch_readable_node(agent.id, node_id),
         :ok <- Nodes.withdraw_node_lineage_claim(node, parsed_claim_id, agent) do
      json(conn, %{ok: true})
    else
      {:error, :invalid_node_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})

      {:error, :claim_not_found} ->
        ApiError.render(conn, :not_found, %{code: "lineage_claim_not_found"})

      {:error, :claim_not_owned} ->
        ApiError.render(conn, :forbidden, %{code: "lineage_claim_not_owned"})

      :error ->
        ApiError.render(conn, :not_found, %{code: "node_not_found"})
    end
  end

  @spec list_links(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list_links(conn, %{"id" => id}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, node_id} <- parse_node_id(id),
         {:ok, node} <- fetch_readable_node(agent.id, node_id) do
      data =
        node
        |> Nodes.list_node_cross_chain_links()
        |> Enum.map(&Lineage.encode_link/1)

      json(conn, %{data: data})
    else
      {:error, :invalid_node_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})

      :error ->
        ApiError.render(conn, :not_found, %{code: "node_not_found"})
    end
  end

  @spec create_link(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_link(conn, %{"id" => id} = params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, node_id} <- parse_node_id(id),
         {:ok, node} <- fetch_readable_node(agent.id, node_id),
         {:ok, link} <- Nodes.create_or_replace_node_cross_chain_link(node, agent, params) do
      json(conn, %{data: Lineage.encode_link(link)})
    else
      {:error, :invalid_node_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})

      {:error, :not_node_author} ->
        ApiError.render(conn, :forbidden, %{code: "node_author_required"})

      {:error, {:required, field}} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "#{field}_required"})

      {:error, :invalid_payload} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_cross_chain_link"})

      {:error, :invalid_relation} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_lineage_relation"})

      {:error, :invalid_target_chain_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_target_chain_id"})

      {:error, :target_node_not_found} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "target_node_not_found"})

      {:error, :target_node_chain_unavailable} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "target_node_chain_unavailable"})

      {:error, :target_chain_mismatch} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "target_chain_mismatch"})

      {:error, %Ecto.Changeset{} = changeset} ->
        ApiError.render(conn, :unprocessable_entity, %{
          code: "cross_chain_link_create_failed",
          details: ApiError.translate_changeset(changeset)
        })

      :error ->
        ApiError.render(conn, :not_found, %{code: "node_not_found"})
    end
  end

  @spec clear_link(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def clear_link(conn, %{"id" => id}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, node_id} <- parse_node_id(id),
         {:ok, node} <- fetch_readable_node(agent.id, node_id),
         :ok <- Nodes.clear_node_cross_chain_link(node, agent) do
      json(conn, %{ok: true})
    else
      {:error, :invalid_node_id} ->
        ApiError.render(conn, :unprocessable_entity, %{code: "invalid_node_id"})

      {:error, :not_node_author} ->
        ApiError.render(conn, :forbidden, %{code: "node_author_required"})

      :error ->
        ApiError.render(conn, :not_found, %{code: "node_not_found"})
    end
  end

  defp fetch_public_node(id) do
    {:ok, Nodes.get_public_node!(id)}
  rescue
    Ecto.NoResultsError -> :error
  end

  defp fetch_readable_node(agent_id, id) do
    {:ok, Nodes.get_readable_node_for_agent!(agent_id, id)}
  rescue
    Ecto.NoResultsError -> :error
  end

  defp parse_node_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_node_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :invalid_node_id}
    end
  end

  defp parse_node_id(_value), do: {:error, :invalid_node_id}
end
