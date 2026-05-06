defmodule TechTree.Tech.RewardAllocation do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:allocation_id, :string, autogenerate: false}
  @lanes ~w(science usdc_input)

  @type t :: %__MODULE__{}

  schema "tech_reward_allocations" do
    field :manifest_id, :string
    field :epoch, :integer
    field :lane, :string
    field :agent_id, :string
    field :wallet_address, :string
    field :amount, :string
    field :allocation_ref, :string
    field :proof, {:array, :string}, default: []
    field :rank, :integer
    field :score, :decimal
    field :leaderboard_id, :string

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(allocation, attrs) do
    allocation
    |> cast(attrs, [
      :allocation_id,
      :manifest_id,
      :epoch,
      :lane,
      :agent_id,
      :wallet_address,
      :amount,
      :allocation_ref,
      :proof,
      :rank,
      :score,
      :leaderboard_id
    ])
    |> validate_required([
      :allocation_id,
      :manifest_id,
      :epoch,
      :lane,
      :agent_id,
      :amount,
      :allocation_ref,
      :rank
    ])
    |> validate_inclusion(:lane, @lanes)
    |> validate_number(:epoch, greater_than_or_equal_to: 0)
    |> validate_number(:rank, greater_than_or_equal_to: 1)
    |> validate_format(:agent_id, ~r/^[0-9]+$/)
    |> validate_format(:amount, ~r/^[0-9]+$/)
    |> validate_format(:allocation_ref, ~r/^0x[0-9a-fA-F]{64}$/)
  end
end
