defmodule TechTree.Nodes.NodeChainReceipt do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          node_id: integer() | nil,
          chain_id: integer() | nil,
          contract_address: String.t() | nil,
          tx_hash: String.t() | nil,
          block_number: integer() | nil,
          log_index: integer() | nil,
          confirmed_at: DateTime.t() | nil
        }

  schema "node_chain_receipts" do
    field :chain_id, :integer
    field :contract_address, :string
    field :tx_hash, :string
    field :block_number, :integer
    field :log_index, :integer
    field :confirmed_at, :utc_datetime_usec

    belongs_to :node, TechTree.Nodes.Node

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [:node_id, :chain_id, :contract_address, :tx_hash, :block_number, :log_index, :confirmed_at])
    |> validate_required([:node_id, :chain_id, :contract_address, :tx_hash, :block_number, :log_index])
    |> foreign_key_constraint(:node_id)
    |> unique_constraint(:node_id)
    |> unique_constraint([:tx_hash, :log_index], name: :node_chain_receipts_tx_log_uidx)
  end
end
