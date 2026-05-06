defmodule TechTree.Tech.Leaderboard do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:leaderboard_id, :string, autogenerate: false}

  @type t :: %__MODULE__{}

  schema "tech_leaderboards" do
    field :kind, :string
    field :title, :string
    field :weight_bps, :integer
    field :starts_epoch, :integer
    field :ends_epoch, :integer
    field :config_hash, :string
    field :uri, :string
    field :active, :boolean, default: true

    belongs_to :created_by_agent, TechTree.Agents.AgentIdentity

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(leaderboard, attrs) do
    leaderboard
    |> cast(attrs, [
      :leaderboard_id,
      :created_by_agent_id,
      :kind,
      :title,
      :weight_bps,
      :starts_epoch,
      :ends_epoch,
      :config_hash,
      :uri,
      :active
    ])
    |> validate_required([:leaderboard_id, :kind, :title, :weight_bps, :config_hash, :uri])
    |> validate_number(:weight_bps, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000)
    |> validate_format(:config_hash, ~r/^0x[0-9a-fA-F]{64}$/)
  end
end
