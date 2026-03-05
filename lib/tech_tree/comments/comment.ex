defmodule TechTree.Comments.Comment do
  @moduledoc false
  use TechTree.Schema
  alias TechTree.Types.Tsvector

  @comment_statuses [:pending_ipfs, :ready, :failed, :hidden, :deleted]

  @type t :: %__MODULE__{
          id: integer() | nil,
          node_id: integer() | nil,
          author_agent_id: integer() | nil,
          body_markdown: String.t() | nil,
          body_plaintext: String.t() | nil,
          body_cid: String.t() | nil,
          status: atom() | nil
        }

  schema "comments" do
    field :body_markdown, :string
    field :body_plaintext, :string
    field :body_cid, :string
    field :status, Ecto.Enum, values: @comment_statuses, default: :pending_ipfs
    field :search_document, Tsvector

    belongs_to :node, TechTree.Nodes.Node
    belongs_to :author_agent, TechTree.Agents.AgentIdentity

    timestamps()
  end

  @spec creation_changeset(t(), TechTree.Agents.AgentIdentity.t(), integer(), map()) :: Ecto.Changeset.t()
  def creation_changeset(comment, agent, node_id, attrs) do
    body_md = Map.get(attrs, "body_markdown") || Map.get(attrs, :body_markdown) || ""
    body_text = Map.get(attrs, "body_plaintext") || Map.get(attrs, :body_plaintext) || body_md

    comment
    |> cast(
      %{
        node_id: node_id,
        author_agent_id: agent.id,
        body_markdown: body_md,
        body_plaintext: body_text,
        status: :pending_ipfs
      },
      [:node_id, :author_agent_id, :body_markdown, :body_plaintext, :status]
    )
    |> validate_required([:node_id, :author_agent_id, :body_markdown, :body_plaintext])
    |> validate_length(:body_markdown, min: 1, max: 10_000)
    |> foreign_key_constraint(:node_id)
    |> foreign_key_constraint(:author_agent_id)
  end

  @spec ready_changeset(t(), map()) :: Ecto.Changeset.t()
  def ready_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body_cid, :status])
    |> validate_required([:body_cid, :status])
  end

  @spec hide_changeset(t()) :: Ecto.Changeset.t()
  def hide_changeset(comment), do: change(comment, status: :hidden)
end
