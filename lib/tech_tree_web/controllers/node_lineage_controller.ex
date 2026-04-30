defmodule TechTreeWeb.NodeLineageController do
  use TechTreeWeb, :controller

  alias TechTree.Nodes
  alias TechTree.Nodes.Lineage
  alias TechTreeWeb.{ApiError, ControllerHelpers}

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    with_public_node(conn, id, fn conn, node ->
      json(conn, %{data: Nodes.cross_chain_lineage(node)})
    end)
  end

  @spec show_private(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show_private(conn, %{"id" => id}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with_readable_node(conn, agent.id, id, fn conn, node ->
      json(conn, %{data: Nodes.cross_chain_lineage(node)})
    end)
  end

  @spec list_claims(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list_claims(conn, %{"id" => id}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with_readable_node(conn, agent.id, id, fn conn, node ->
      data =
        node
        |> Nodes.list_node_lineage_claims()
        |> Enum.map(&Lineage.encode_claim_history/1)

      json(conn, %{data: data})
    end)
  end

  @spec create_claim(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_claim(conn, %{"id" => id} = params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with_readable_node(conn, agent.id, id, fn conn, node ->
      case Nodes.create_node_lineage_claim(node, agent, params) do
        {:ok, claim} ->
          conn
          |> put_status(:created)
          |> json(%{data: Lineage.encode_claim_history(claim)})

        error ->
          render_claim_error(conn, error)
      end
    end)
  end

  @spec withdraw_claim(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def withdraw_claim(conn, %{"id" => id, "claim_id" => claim_id}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with_readable_node_claim(conn, agent.id, id, claim_id, fn conn, node, parsed_claim_id ->
      case Nodes.withdraw_node_lineage_claim(node, parsed_claim_id, agent) do
        :ok ->
          json(conn, %{ok: true})

        error ->
          render_claim_error(conn, error)
      end
    end)
  end

  @spec list_links(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list_links(conn, %{"id" => id}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with_readable_node(conn, agent.id, id, fn conn, node ->
      data =
        node
        |> Nodes.list_node_cross_chain_links()
        |> Enum.map(&Lineage.encode_link/1)

      json(conn, %{data: data})
    end)
  end

  @spec create_link(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_link(conn, %{"id" => id} = params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with_readable_node(conn, agent.id, id, fn conn, node ->
      case Nodes.create_or_replace_node_cross_chain_link(node, agent, params) do
        {:ok, link} ->
          json(conn, %{data: Lineage.encode_link(link)})

        error ->
          render_link_error(conn, error)
      end
    end)
  end

  @spec clear_link(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def clear_link(conn, %{"id" => id}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with_readable_node(conn, agent.id, id, fn conn, node ->
      case Nodes.clear_node_cross_chain_link(node, agent) do
        :ok ->
          json(conn, %{ok: true})

        error ->
          render_link_error(conn, error)
      end
    end)
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

  defp with_public_node(conn, id, callback) do
    with {:ok, node_id} <- parse_node_id(id),
         {:ok, node} <- fetch_public_node(node_id) do
      callback.(conn, node)
    else
      {:error, :invalid_node_id} -> render_invalid_node_id(conn)
      :error -> render_node_not_found(conn)
    end
  end

  defp with_readable_node(conn, agent_id, id, callback) do
    with {:ok, node_id} <- parse_node_id(id),
         {:ok, node} <- fetch_readable_node(agent_id, node_id) do
      callback.(conn, node)
    else
      error -> render_node_error(conn, error)
    end
  end

  defp with_readable_node_claim(conn, agent_id, id, claim_id, callback) do
    with {:ok, node_id} <- parse_node_id(id),
         {:ok, parsed_claim_id} <- parse_claim_id(claim_id),
         {:ok, node} <- fetch_readable_node(agent_id, node_id) do
      callback.(conn, node, parsed_claim_id)
    else
      {:error, :invalid_claim_id} -> render_claim_error(conn, {:error, :invalid_claim_id})
      error -> render_node_error(conn, error)
    end
  end

  defp render_node_error(conn, {:error, :invalid_node_id}), do: render_invalid_node_id(conn)
  defp render_node_error(conn, :error), do: render_node_not_found(conn)

  defp render_claim_error(conn, {:error, :invalid_claim_id}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_claim_id"})

  defp render_claim_error(conn, {:error, {:required, field}}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "#{field}_required"})

  defp render_claim_error(conn, {:error, :invalid_payload}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_lineage_payload"})

  defp render_claim_error(conn, {:error, :invalid_relation}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_lineage_relation"})

  defp render_claim_error(conn, {:error, :invalid_target_chain_id}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_target_chain_id"})

  defp render_claim_error(conn, {:error, :target_node_not_found}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "target_node_not_found"})

  defp render_claim_error(conn, {:error, :target_node_chain_unavailable}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "target_node_chain_unavailable"})

  defp render_claim_error(conn, {:error, :target_chain_mismatch}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "target_chain_mismatch"})

  defp render_claim_error(conn, {:error, :claim_not_found}),
    do: ApiError.render(conn, :not_found, %{"code" => "lineage_claim_not_found"})

  defp render_claim_error(conn, {:error, :claim_not_owned}),
    do: ApiError.render(conn, :forbidden, %{"code" => "lineage_claim_not_owned"})

  defp render_claim_error(conn, {:error, %Ecto.Changeset{} = changeset}) do
    ApiError.render(conn, :unprocessable_entity, %{
      "code" => "lineage_claim_create_failed",
      "details" => ApiError.translate_changeset(changeset)
    })
  end

  defp render_link_error(conn, {:error, :not_node_author}),
    do: ApiError.render(conn, :forbidden, %{"code" => "node_author_required"})

  defp render_link_error(conn, {:error, {:required, field}}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "#{field}_required"})

  defp render_link_error(conn, {:error, :invalid_payload}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_cross_chain_link"})

  defp render_link_error(conn, {:error, :invalid_relation}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_lineage_relation"})

  defp render_link_error(conn, {:error, :invalid_target_chain_id}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_target_chain_id"})

  defp render_link_error(conn, {:error, :target_node_not_found}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "target_node_not_found"})

  defp render_link_error(conn, {:error, :target_node_chain_unavailable}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "target_node_chain_unavailable"})

  defp render_link_error(conn, {:error, :target_chain_mismatch}),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "target_chain_mismatch"})

  defp render_link_error(conn, {:error, %Ecto.Changeset{} = changeset}) do
    ApiError.render(conn, :unprocessable_entity, %{
      "code" => "cross_chain_link_create_failed",
      "details" => ApiError.translate_changeset(changeset)
    })
  end

  defp render_invalid_node_id(conn),
    do: ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_node_id"})

  defp render_node_not_found(conn),
    do: ApiError.render(conn, :not_found, %{"code" => "node_not_found"})

  defp parse_node_id(value) do
    case ControllerHelpers.parse_positive_int(value) do
      {:ok, node_id} -> {:ok, node_id}
      {:error, _reason} -> {:error, :invalid_node_id}
    end
  end

  defp parse_claim_id(value) do
    case ControllerHelpers.parse_positive_int(value) do
      {:ok, claim_id} -> {:ok, claim_id}
      {:error, _reason} -> {:error, :invalid_claim_id}
    end
  end
end
