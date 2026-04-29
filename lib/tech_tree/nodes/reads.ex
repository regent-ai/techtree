defmodule TechTree.Nodes.Reads do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Autoskill
  alias TechTree.Agents.AgentIdentity
  alias TechTree.NodeAccess
  alias TechTree.Nodes.{Lineage, Node, NodeTagEdge}
  alias TechTree.QueryHelpers
  alias TechTree.Repo

  @semver_core_regex "^[0-9]+\\.[0-9]+\\.[0-9]+$"

  @spec list_public_seed_roots() :: [Node.t()]
  def list_public_seed_roots do
    public_nodes_query()
    |> where([n, _creator], is_nil(n.parent_id))
    |> order_by([n, _creator], asc: n.inserted_at)
    |> Repo.all()
    |> Autoskill.attach_projection()
    |> NodeAccess.attach_projection()
  end

  @spec list_public_nodes(map()) :: [Node.t()]
  def list_public_nodes(params) do
    limit = QueryHelpers.parse_limit(params, 50)
    cursor = QueryHelpers.parse_cursor(params)

    public_nodes_query()
    |> maybe_before_cursor(cursor)
    |> order_by([n, _creator], desc: n.activity_score, desc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Autoskill.attach_projection()
    |> NodeAccess.attach_projection()
  end

  @spec list_recent_public_nodes(map()) :: [Node.t()]
  def list_recent_public_nodes(params) do
    limit = QueryHelpers.parse_limit(params, 50)
    cursor = QueryHelpers.parse_cursor(params)

    public_nodes_query()
    |> maybe_before_cursor(cursor)
    |> order_by([n, _creator], desc: n.inserted_at, desc: n.id)
    |> limit(^limit)
    |> Repo.all()
    |> Autoskill.attach_projection()
    |> NodeAccess.attach_projection()
  end

  @spec get_public_node!(integer() | String.t()) :: Node.t()
  def get_public_node!(id) do
    normalized_id = QueryHelpers.normalize_id(id)

    tag_edges_query =
      NodeTagEdge
      |> where([e], e.dst_node_id in subquery(public_node_ids_query()))
      |> order_by([e], asc: e.ordinal)

    public_nodes_query()
    |> where([n, _creator], n.id == ^normalized_id)
    |> limit(1)
    |> Repo.one!()
    |> Repo.preload([:creator_agent, tag_edges_out: tag_edges_query])
    |> Lineage.attach_projection()
    |> Autoskill.attach_projection()
    |> NodeAccess.attach_projection()
  end

  @spec get_readable_node_for_agent!(integer(), integer() | String.t()) :: Node.t()
  def get_readable_node_for_agent!(agent_id, id) when is_integer(agent_id) and agent_id > 0 do
    normalized_id = QueryHelpers.normalize_id(id)

    tag_edges_query =
      NodeTagEdge
      |> where([e], e.src_node_id == ^normalized_id)
      |> order_by([e], asc: e.ordinal)

    readable_nodes_query(agent_id)
    |> where([n, _creator], n.id == ^normalized_id)
    |> limit(1)
    |> Repo.one!()
    |> Repo.preload([:creator_agent, tag_edges_out: tag_edges_query])
    |> Lineage.attach_projection()
    |> Autoskill.attach_projection()
    |> NodeAccess.attach_projection()
  end

  @spec list_public_children(integer() | String.t(), map()) :: [Node.t()]
  def list_public_children(id, params) do
    parent_id = QueryHelpers.normalize_id(id)
    limit = QueryHelpers.parse_limit(params, 100)
    cursor = QueryHelpers.parse_cursor(params)

    public_nodes_query()
    |> where([n, _creator], n.parent_id == ^parent_id)
    |> where([n, _creator], n.parent_id in subquery(public_node_ids_query()))
    |> maybe_before_cursor(cursor)
    |> order_by([n, _creator], desc: n.activity_score, asc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Autoskill.attach_projection()
    |> NodeAccess.attach_projection()
  end

  @spec list_readable_children(integer(), integer() | String.t(), map()) :: [Node.t()]
  def list_readable_children(agent_id, id, params) when is_integer(agent_id) and agent_id > 0 do
    parent_id = QueryHelpers.normalize_id(id)
    limit = QueryHelpers.parse_limit(params, 100)
    cursor = QueryHelpers.parse_cursor(params)

    readable_nodes_query(agent_id)
    |> where([n, _creator], n.parent_id == ^parent_id)
    |> maybe_before_cursor(cursor)
    |> order_by([n, _creator], desc: n.activity_score, asc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Autoskill.attach_projection()
    |> NodeAccess.attach_projection()
  end

  @spec list_tagged_edges(integer() | String.t()) :: [NodeTagEdge.t()]
  def list_tagged_edges(id) do
    node_id = QueryHelpers.normalize_id(id)

    NodeTagEdge
    |> where([e], e.src_node_id == ^node_id)
    |> where([e], e.src_node_id in subquery(public_node_ids_query()))
    |> where([e], e.dst_node_id in subquery(public_node_ids_query()))
    |> order_by([e], asc: e.ordinal)
    |> Repo.all()
  end

  @spec list_hot_nodes(String.t(), map()) :: [Node.t()]
  def list_hot_nodes(seed, params) do
    limit = QueryHelpers.parse_limit(params, 25)
    cursor = QueryHelpers.parse_cursor(params)

    public_nodes_query()
    |> where([n, _creator], n.seed == ^seed)
    |> maybe_before_cursor(cursor)
    |> order_by([n, _creator], desc: n.activity_score, desc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Autoskill.attach_projection()
    |> NodeAccess.attach_projection()
  end

  @spec list_public_nodes_by_ids([integer() | String.t()]) :: [Node.t()]
  def list_public_nodes_by_ids(ids) when is_list(ids) do
    normalized_ids =
      ids
      |> Enum.reduce([], fn
        id, acc when is_integer(id) or is_binary(id) -> [QueryHelpers.normalize_id(id) | acc]
        _id, acc -> acc
      end)
      |> Enum.uniq()

    case normalized_ids do
      [] ->
        []

      _ ->
        public_nodes_query()
        |> where([n, _creator], n.id in ^normalized_ids)
        |> Repo.all()
        |> Autoskill.attach_projection()
        |> NodeAccess.attach_projection()
    end
  end

  @spec get_skill_by_slug_and_version(String.t(), String.t()) :: Node.t() | nil
  def get_skill_by_slug_and_version(slug, version) when is_binary(slug) and is_binary(version) do
    public_skill_nodes_query()
    |> where([n, _creator], n.skill_slug == ^slug and n.skill_version == ^version)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      node -> node |> Autoskill.attach_projection() |> NodeAccess.attach_projection()
    end
  end

  @spec get_latest_skill(String.t()) :: Node.t() | nil
  def get_latest_skill(slug) when is_binary(slug) do
    public_skill_nodes_query()
    |> where([n, _creator], n.skill_slug == ^slug)
    |> where([n, _creator], fragment("? ~ ?", n.skill_version, ^@semver_core_regex))
    |> order_by(
      [n, _creator],
      desc: fragment("CAST(split_part(?, '.', 1) AS integer)", n.skill_version),
      desc: fragment("CAST(split_part(?, '.', 2) AS integer)", n.skill_version),
      desc: fragment("CAST(split_part(?, '.', 3) AS integer)", n.skill_version),
      desc: n.inserted_at
    )
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      node -> node |> Autoskill.attach_projection() |> NodeAccess.attach_projection()
    end
  end

  @spec public_nodes_query() :: Ecto.Query.t()
  def public_nodes_query do
    Node
    |> join(:inner, [n], creator in AgentIdentity, on: creator.id == n.creator_agent_id)
    |> where([n, creator], n.status == :anchored and creator.status == "active")
  end

  @spec readable_nodes_query(integer()) :: Ecto.Query.t()
  def readable_nodes_query(agent_id) do
    Node
    |> join(:inner, [n], creator in AgentIdentity, on: creator.id == n.creator_agent_id)
    |> where(
      [n, creator],
      (n.status == :anchored and creator.status == "active") or
        (n.creator_agent_id == ^agent_id and n.status in [:pinned, :anchored])
    )
  end

  @spec public_node_ids_query() :: Ecto.Query.t()
  def public_node_ids_query do
    public_nodes_query()
    |> select([n, _creator], n.id)
  end

  @spec maybe_before_cursor(Ecto.Query.t(), integer() | nil) :: Ecto.Query.t()
  defp maybe_before_cursor(query, nil), do: query
  defp maybe_before_cursor(query, cursor), do: where(query, [n, _creator], n.id < ^cursor)

  @spec normalize_id(integer() | String.t()) :: integer()
  def normalize_id(value), do: QueryHelpers.normalize_id(value)

  defp public_skill_nodes_query do
    public_nodes_query()
    |> where(
      [n, _creator],
      n.kind == :skill and not is_nil(n.skill_slug) and not is_nil(n.skill_version)
    )
    |> where([n, _creator], fragment("btrim(coalesce(?, '')) <> ''", n.skill_md_body))
  end
end
