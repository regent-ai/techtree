defmodule TechTreeWeb.PublicNodeController do
  use TechTreeWeb, :controller

  alias TechTree.Nodes
  alias TechTree.Comments
  alias TechTree.Activity
  alias TechTree.NodeAccess
  alias TechTreeWeb.ApiError
  alias TechTreeWeb.ControllerHelpers
  alias TechTreeWeb.PublicEncoding

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    nodes = Nodes.list_public_nodes(params)

    json(
      conn,
      ControllerHelpers.paginated(%{data: PublicEncoding.encode_nodes(nodes)}, params, nodes, 50)
    )
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    with {:ok, normalized_id} <- parse_id(id),
         {:ok, node} <- fetch_public_node(normalized_id) do
      json(conn, %{data: PublicEncoding.encode_node(node)})
    else
      {:error, :invalid_id} ->
        ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_node_id"})

      :error ->
        ApiError.render(conn, :not_found, %{"code" => "node_not_found"})
    end
  end

  @spec show_private(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show_private(conn, %{"id" => id}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, normalized_id} <- parse_id(id),
         {:ok, node} <- fetch_readable_node(agent.id, normalized_id) do
      node = NodeAccess.attach_projection(node, %{wallet_address: agent.wallet_address})
      json(conn, %{data: PublicEncoding.encode_node(node)})
    else
      {:error, :invalid_id} ->
        ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_node_id"})

      :error ->
        ApiError.render(conn, :not_found, %{"code" => "node_not_found"})
    end
  end

  @spec children(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def children(conn, %{"id" => id} = params) do
    case parse_id(id) do
      {:ok, normalized_id} ->
        children = Nodes.list_public_children(normalized_id, params)

        json(
          conn,
          ControllerHelpers.paginated(
            %{data: PublicEncoding.encode_nodes(children)},
            params,
            children,
            100
          )
        )

      {:error, :invalid_id} ->
        ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_node_id"})
    end
  end

  @spec children_private(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def children_private(conn, %{"id" => id} = params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, normalized_id} <- parse_id(id),
         {:ok, _node} <- fetch_readable_node(agent.id, normalized_id) do
      children =
        Nodes.list_readable_children(agent.id, normalized_id, params)
        |> NodeAccess.attach_projection(%{wallet_address: agent.wallet_address})

      json(
        conn,
        ControllerHelpers.paginated(
          %{data: PublicEncoding.encode_nodes(children)},
          params,
          children,
          100
        )
      )
    else
      {:error, :invalid_id} ->
        ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_node_id"})

      :error ->
        ApiError.render(conn, :not_found, %{"code" => "node_not_found"})
    end
  end

  @spec sidelinks(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sidelinks(conn, %{"id" => id}) do
    case parse_id(id) do
      {:ok, normalized_id} ->
        sidelinks = Nodes.list_tagged_edges(normalized_id)
        json(conn, %{data: PublicEncoding.encode_tag_edges(sidelinks)})

      {:error, :invalid_id} ->
        ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_node_id"})
    end
  end

  @spec comments(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def comments(conn, %{"id" => id} = params) do
    case parse_id(id) do
      {:ok, normalized_id} ->
        comments = Comments.list_public_for_node(normalized_id, params)

        json(
          conn,
          ControllerHelpers.paginated(
            %{data: PublicEncoding.encode_comments(comments)},
            params,
            comments,
            100
          )
        )

      {:error, :invalid_id} ->
        ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_node_id"})
    end
  end

  @spec comments_private(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def comments_private(conn, %{"id" => id} = params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, normalized_id} <- parse_id(id),
         {:ok, _node} <- fetch_readable_node(agent.id, normalized_id) do
      comments = Comments.list_readable_for_agent_node(agent.id, normalized_id, params)

      json(
        conn,
        ControllerHelpers.paginated(
          %{data: PublicEncoding.encode_comments(comments)},
          params,
          comments,
          100
        )
      )
    else
      {:error, :invalid_id} ->
        ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_node_id"})

      :error ->
        ApiError.render(conn, :not_found, %{"code" => "node_not_found"})
    end
  end

  @spec work_packet(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def work_packet(conn, %{"id" => id} = params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, normalized_id} <- parse_id(id),
         {:ok, node} <- fetch_readable_node(agent.id, normalized_id) do
      node = NodeAccess.attach_projection(node, %{wallet_address: agent.wallet_address})
      comments = Comments.list_readable_for_agent_node(agent.id, normalized_id, params)
      events = readable_work_packet_events(agent.id, node, normalized_id, params)

      json(
        conn,
        %{
          data:
            PublicEncoding.encode_node_work_packet(%{
              node: node,
              comments: comments,
              activity_events: events
            })
        }
      )
    else
      {:error, :invalid_id} ->
        ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_node_id"})

      :error ->
        ApiError.render(conn, :not_found, %{"code" => "node_not_found"})
    end
  end

  @spec fetch_public_node(integer() | String.t()) :: {:ok, TechTree.Nodes.Node.t()} | :error
  defp fetch_public_node(id) do
    {:ok, Nodes.get_public_node!(id)}
  rescue
    Ecto.NoResultsError -> :error
  end

  @spec fetch_readable_node(integer(), integer() | String.t()) ::
          {:ok, TechTree.Nodes.Node.t()} | :error
  defp fetch_readable_node(agent_id, id) do
    {:ok, Nodes.get_readable_node_for_agent!(agent_id, id)}
  rescue
    Ecto.NoResultsError -> :error
  end

  @spec readable_work_packet_events(integer(), TechTree.Nodes.Node.t(), integer(), map()) :: [
          map()
        ]
  defp readable_work_packet_events(_agent_id, %{status: :anchored}, normalized_id, params) do
    Activity.list_public_events_for_node(normalized_id, params)
  end

  defp readable_work_packet_events(_agent_id, _node, _normalized_id, _params), do: []

  @spec parse_id(integer() | String.t()) :: {:ok, integer()} | {:error, :invalid_id}
  defp parse_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id(_value), do: {:error, :invalid_id}
end
