defmodule TechTree.Agents.AgentIdentity do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          chain_id: integer() | nil,
          registry_address: String.t() | nil,
          token_id: Decimal.t() | nil,
          wallet_address: String.t() | nil,
          label: String.t() | nil,
          status: String.t() | nil,
          last_verified_at: DateTime.t() | nil
        }

  schema "agent_identities" do
    field :chain_id, :integer
    field :registry_address, :string
    field :token_id, :decimal
    field :wallet_address, :string
    field :label, :string
    field :status, :string, default: "active"
    field :last_verified_at, :utc_datetime_usec

    has_many :created_nodes, TechTree.Nodes.Node, foreign_key: :creator_agent_id
    has_many :comments, TechTree.Comments.Comment, foreign_key: :author_agent_id

    timestamps()
  end

  @spec upsert_changeset(t(), map()) :: Ecto.Changeset.t()
  def upsert_changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :chain_id,
      :registry_address,
      :token_id,
      :wallet_address,
      :label,
      :status,
      :last_verified_at
    ])
    |> validate_required([:chain_id, :registry_address, :token_id, :wallet_address])
    |> validate_number(:chain_id, greater_than: 0)
    |> unique_constraint([:chain_id, :registry_address, :token_id],
      name: :agent_identities_chain_registry_token_uidx
    )
  end
end
