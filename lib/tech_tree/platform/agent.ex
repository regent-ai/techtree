defmodule TechTree.Platform.Agent do
  @moduledoc false
  use TechTree.Schema

  @type t :: %__MODULE__{}

  schema "platform_agents" do
    field :slug, :string
    field :source, :string
    field :display_name, :string
    field :summary, :string
    field :status, :string, default: "active"
    field :owner_address, :string
    field :feature_tags, {:array, :string}, default: []
    field :chain_id, :integer
    field :token_id, :decimal
    field :agent_uri, :string
    field :external_url, :string

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :slug,
      :source,
      :display_name,
      :summary,
      :status,
      :owner_address,
      :feature_tags,
      :chain_id,
      :token_id,
      :agent_uri,
      :external_url
    ])
    |> validate_required([:slug, :source, :display_name, :status])
    |> validate_length(:slug, min: 1, max: 200)
    |> validate_length(:display_name, min: 1, max: 200)
    |> unique_constraint(:slug)
  end
end
