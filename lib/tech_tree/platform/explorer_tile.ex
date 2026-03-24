defmodule TechTree.Platform.ExplorerTile do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{}

  schema "platform_explorer_tiles" do
    field :coord_key, :string
    field :x, :integer
    field :y, :integer
    field :title, :string
    field :summary, :string
    field :shader_key, :string
    field :terrain, :string
    field :unlock_status, :string, default: "imported"
    field :owner_address, :string
    field :metadata, :map, default: %{}
    field :payment_credit_id, :string

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(tile, attrs) do
    tile
    |> cast(attrs, [
      :coord_key,
      :x,
      :y,
      :title,
      :summary,
      :shader_key,
      :terrain,
      :unlock_status,
      :owner_address,
      :metadata,
      :payment_credit_id
    ])
    |> validate_required([:coord_key, :x, :y, :title])
    |> unique_constraint(:coord_key)
  end
end
