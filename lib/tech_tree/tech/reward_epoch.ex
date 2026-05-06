defmodule TechTree.Tech.RewardEpoch do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:epoch, :integer, autogenerate: false}
  @statuses ~w(planned open sealed posted)

  @type t :: %__MODULE__{}

  schema "tech_reward_epochs" do
    field :status, :string, default: "planned"
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec
    field :total_emission_amount, :string, default: "0"
    field :science_budget_amount, :string, default: "0"
    field :input_budget_amount, :string, default: "0"

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(epoch, attrs) do
    epoch
    |> cast(attrs, [
      :epoch,
      :status,
      :starts_at,
      :ends_at,
      :total_emission_amount,
      :science_budget_amount,
      :input_budget_amount
    ])
    |> validate_required([
      :epoch,
      :status,
      :total_emission_amount,
      :science_budget_amount,
      :input_budget_amount
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:epoch, greater_than_or_equal_to: 0)
    |> validate_amount(:total_emission_amount)
    |> validate_amount(:science_budget_amount)
    |> validate_amount(:input_budget_amount)
  end

  defp validate_amount(changeset, field), do: validate_format(changeset, field, ~r/^[0-9]+$/)
end
