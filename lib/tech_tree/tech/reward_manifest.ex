defmodule TechTree.Tech.RewardManifest do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:manifest_id, :string, autogenerate: false}
  @lanes ~w(science usdc_input)
  @statuses ~w(prepared posted retired)

  @type t :: %__MODULE__{}

  schema "tech_reward_manifests" do
    field :epoch, :integer
    field :lane, :string
    field :merkle_root, :string
    field :manifest_hash, :string
    field :total_allocated_amount, :string
    field :allocation_count, :integer, default: 0
    field :policy_version, :string
    field :leaderboard_ids, {:array, :string}, default: []
    field :reputation_filter_version, :string
    field :dust_policy, :map, default: %{}
    field :challenge_ends_at, :integer
    field :status, :string, default: "prepared"

    has_many :allocations, TechTree.Tech.RewardAllocation,
      foreign_key: :manifest_id,
      references: :manifest_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(manifest, attrs) do
    manifest
    |> cast(attrs, [
      :manifest_id,
      :epoch,
      :lane,
      :merkle_root,
      :manifest_hash,
      :total_allocated_amount,
      :allocation_count,
      :policy_version,
      :leaderboard_ids,
      :reputation_filter_version,
      :dust_policy,
      :challenge_ends_at,
      :status
    ])
    |> validate_required([
      :manifest_id,
      :epoch,
      :lane,
      :merkle_root,
      :manifest_hash,
      :total_allocated_amount,
      :policy_version,
      :reputation_filter_version,
      :status
    ])
    |> validate_number(:epoch, greater_than_or_equal_to: 0)
    |> validate_number(:allocation_count, greater_than_or_equal_to: 0)
    |> validate_inclusion(:lane, @lanes)
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:merkle_root, ~r/^0x[0-9a-fA-F]{64}$/)
    |> validate_format(:manifest_hash, ~r/^0x[0-9a-fA-F]{64}$/)
    |> validate_format(:total_allocated_amount, ~r/^[0-9]+$/)
  end
end
