defmodule TechTree.Platform do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Platform.{
    Agent,
    BasenameMintAllowance,
    BasenamePaymentCredit,
    EnsSubnameClaim,
    ExplorerTile,
    NameClaim,
    RedeemClaim
  }

  alias TechTree.NodeAccess
  alias TechTree.Repo

  @spec dashboard_snapshot() :: map()
  def dashboard_snapshot do
    %{
      counts: %{
        agents: Repo.aggregate(Agent, :count, :id),
        tiles: Repo.aggregate(ExplorerTile, :count, :id),
        names: Repo.aggregate(NameClaim, :count, :id),
        redeems: Repo.aggregate(RedeemClaim, :count, :id)
      },
      recent_agents: list_agents(limit: 6),
      facilitator: facilitator_snapshot()
    }
  end

  @spec facilitator_snapshot() :: map()
  def facilitator_snapshot do
    base_url = normalize_optional_text(System.get_env("FACILITATOR_API_BASE_URL"))

    %{
      base_url: base_url,
      status: if(base_url, do: :configured, else: :missing)
    }
  end

  @spec get_agent_by_slug(String.t()) :: Agent.t() | nil
  def get_agent_by_slug(slug) when is_binary(slug) do
    slug
    |> normalize_optional_text()
    |> case do
      nil ->
        nil

      normalized ->
        case Repo.get_by(Agent, slug: normalized) do
          nil ->
            nil

          agent ->
            %{agent | seller_summary: NodeAccess.seller_summary_for_wallet(agent.owner_address)}
        end
    end
  end

  @spec list_agents(keyword()) :: [Agent.t()]
  def list_agents(opts \\ []) do
    limit = Keyword.get(opts, :limit, 12)
    search = normalize_optional_text(Keyword.get(opts, :search))
    status = normalize_optional_text(Keyword.get(opts, :status))

    Agent
    |> maybe_filter_status(status)
    |> maybe_filter_search(search)
    |> order_by([a], desc: a.inserted_at, desc: a.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec explorer_snapshot() :: map()
  def explorer_snapshot do
    tiles = list_explorer_tiles()
    children_by_parent = Enum.group_by(tiles, &parent_coord_key/1)
    root_tiles = Map.get(children_by_parent, nil, [])

    %{
      tiles: tiles,
      root_tiles: root_tiles,
      children_by_parent: children_by_parent,
      tiles_by_coord: Map.new(tiles, &{&1.coord_key, &1})
    }
  end

  @spec explorer_view_tiles(map(), [String.t()]) :: [ExplorerTile.t()]
  def explorer_view_tiles(snapshot, path)
      when is_map(snapshot) and is_list(path) do
    case List.last(path) do
      nil -> Map.get(snapshot.children_by_parent, nil, [])
      coord -> Map.get(snapshot.children_by_parent, coord, [])
    end
  end

  @spec explorer_child_count(map(), String.t()) :: non_neg_integer()
  def explorer_child_count(snapshot, coord_key) when is_map(snapshot) and is_binary(coord_key) do
    snapshot
    |> Map.get(:children_by_parent, %{})
    |> Map.get(coord_key, [])
    |> length()
  end

  @spec explorer_tile(map(), String.t()) :: ExplorerTile.t() | nil
  def explorer_tile(snapshot, coord_key) when is_map(snapshot) and is_binary(coord_key) do
    Map.get(snapshot.tiles_by_coord, coord_key)
  end

  @spec list_tiles_json() :: [map()]
  def list_tiles_json do
    tiles = list_explorer_tiles()

    tiles
    |> Enum.map(fn tile ->
      %{
        coord_key: tile.coord_key,
        x: tile.x,
        y: tile.y,
        title: tile.title,
        terrain: tile.terrain,
        owner_address: tile.owner_address,
        parent_coord_key: parent_coord_key(tile),
        child_count: 0
      }
    end)
    |> attach_child_counts()
  end

  @spec names_snapshot() :: map()
  def names_snapshot do
    recent = list_name_claims(limit: 10)
    allowances = list_basename_mint_allowances(limit: 10)
    credits = list_basename_payment_credits(limit: 10)
    ens_claims = list_ens_subname_claims(limit: 10)

    %{
      recent: recent,
      allowances: allowances,
      credits: credits,
      ens_claims: ens_claims,
      available_credit_count: Repo.aggregate(BasenamePaymentCredit, :count, :id),
      ens_claim_count: Repo.aggregate(EnsSubnameClaim, :count, :id),
      allowance_count: Repo.aggregate(BasenameMintAllowance, :count, :id)
    }
  end

  @spec redeem_snapshot() :: map()
  def redeem_snapshot do
    %{claims: list_redeem_claims(limit: 20)}
  end

  @spec list_name_claims(keyword()) :: [NameClaim.t()]
  def list_name_claims(opts \\ []) do
    NameClaim
    |> order_by([row], desc: row.inserted_at, desc: row.id)
    |> limit(^Keyword.get(opts, :limit, 10))
    |> Repo.all()
  end

  @spec list_basename_mint_allowances(keyword()) :: [BasenameMintAllowance.t()]
  def list_basename_mint_allowances(opts \\ []) do
    BasenameMintAllowance
    |> order_by([row], desc: row.inserted_at, desc: row.id)
    |> limit(^Keyword.get(opts, :limit, 10))
    |> Repo.all()
  end

  @spec list_basename_payment_credits(keyword()) :: [BasenamePaymentCredit.t()]
  def list_basename_payment_credits(opts \\ []) do
    BasenamePaymentCredit
    |> order_by([row], desc: row.inserted_at, desc: row.id)
    |> limit(^Keyword.get(opts, :limit, 10))
    |> Repo.all()
  end

  @spec list_ens_subname_claims(keyword()) :: [EnsSubnameClaim.t()]
  def list_ens_subname_claims(opts \\ []) do
    EnsSubnameClaim
    |> order_by([row], desc: row.inserted_at, desc: row.id)
    |> limit(^Keyword.get(opts, :limit, 10))
    |> Repo.all()
  end

  @spec list_redeem_claims(keyword()) :: [RedeemClaim.t()]
  def list_redeem_claims(opts \\ []) do
    RedeemClaim
    |> order_by([row], desc: row.inserted_at, desc: row.id)
    |> limit(^Keyword.get(opts, :limit, 10))
    |> Repo.all()
  end

  defp list_explorer_tiles do
    ExplorerTile
    |> order_by([row], asc: row.inserted_at, asc: row.id)
    |> Repo.all()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, [a], a.status == ^status)

  defp maybe_filter_search(query, nil), do: query
  defp maybe_filter_search(query, ""), do: query

  defp maybe_filter_search(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [a],
      ilike(a.slug, ^pattern) or ilike(a.display_name, ^pattern) or
        ilike(coalesce(a.summary, ""), ^pattern)
    )
  end

  defp attach_child_counts(rows) do
    counts =
      rows
      |> Enum.group_by(& &1.parent_coord_key)
      |> Map.new(fn {key, children} -> {key, length(children)} end)

    Enum.map(rows, fn row ->
      %{row | child_count: Map.get(counts, row.coord_key, 0)}
    end)
  end

  defp parent_coord_key(%ExplorerTile{metadata: metadata}) when is_map(metadata) do
    normalize_optional_text(
      Map.get(metadata, "parent_coord_key") || Map.get(metadata, :parent_coord_key)
    )
  end

  defp parent_coord_key(_tile), do: nil

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_text(_value), do: nil
end
