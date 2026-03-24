defmodule TechTree.Platform.BasenameMintAllowance do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{}

  schema "platform_basename_mint_allowances" do
    field :parent_node, :string
    field :parent_name, :string
    field :address, :string
    field :snapshot_block_number, :integer
    field :snapshot_total, :integer
    field :free_mints_used, :integer, default: 0

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :parent_node,
      :parent_name,
      :address,
      :snapshot_block_number,
      :snapshot_total,
      :free_mints_used
    ])
    |> validate_required([
      :parent_node,
      :parent_name,
      :address,
      :snapshot_block_number,
      :snapshot_total
    ])
    |> unique_constraint([:parent_node, :address])
  end
end
