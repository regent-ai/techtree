defmodule TechTree.Tech.Withdrawal do
  @moduledoc false
  use TechTree.Schema

  @primary_key {:withdrawal_id, :string, autogenerate: false}
  @statuses ~w(prepared submitted confirmed failed)

  @type t :: %__MODULE__{}

  schema "tech_withdrawals" do
    field :agent_id, :string
    field :amount, :string
    field :tech_recipient, :string
    field :regent_recipient, :string
    field :min_regent_out, :string
    field :deadline, :integer
    field :status, :string, default: "prepared"
    field :transaction, :map, default: %{}
    field :tx_hash, :string

    belongs_to :agent_identity, TechTree.Agents.AgentIdentity

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(withdrawal, attrs) do
    withdrawal
    |> cast(attrs, [
      :withdrawal_id,
      :agent_identity_id,
      :agent_id,
      :amount,
      :tech_recipient,
      :regent_recipient,
      :min_regent_out,
      :deadline,
      :status,
      :transaction,
      :tx_hash
    ])
    |> validate_required([
      :withdrawal_id,
      :agent_id,
      :amount,
      :tech_recipient,
      :regent_recipient,
      :min_regent_out,
      :deadline,
      :status,
      :transaction
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:deadline, greater_than: 0)
    |> validate_format(:agent_id, ~r/^[0-9]+$/)
    |> validate_format(:amount, ~r/^[0-9]+$/)
    |> validate_format(:min_regent_out, ~r/^[1-9][0-9]*$/)
    |> validate_format(:tech_recipient, ~r/^0x[0-9a-fA-F]{40}$/)
    |> validate_format(:regent_recipient, ~r/^0x[0-9a-fA-F]{40}$/)
  end
end
