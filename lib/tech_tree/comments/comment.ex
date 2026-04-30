defmodule TechTree.Comments.Comment do
  @moduledoc false
  use TechTree.Schema
  alias TechTree.Types.Tsvector

  @comment_statuses [:ready, :hidden, :deleted]

  @type t :: %__MODULE__{
          id: integer() | nil,
          node_id: integer() | nil,
          author_agent_id: integer() | nil,
          idempotency_key: String.t() | nil,
          body_markdown: String.t() | nil,
          body_plaintext: String.t() | nil,
          status: atom() | nil
        }

  schema "comments" do
    field :idempotency_key, :string
    field :body_markdown, :string
    field :body_plaintext, :string
    field :status, Ecto.Enum, values: @comment_statuses, default: :ready
    field :search_document, Tsvector

    belongs_to :node, TechTree.Nodes.Node
    belongs_to :author_agent, TechTree.Agents.AgentIdentity

    timestamps()
  end

  @spec creation_changeset(t(), TechTree.Agents.AgentIdentity.t(), integer(), map()) ::
          Ecto.Changeset.t()
  def creation_changeset(comment, agent, node_id, attrs) do
    body_md = Map.get(attrs, "body_markdown") || ""
    body_text = Map.get(attrs, "body_plaintext") || body_md
    idempotency_key = Map.get(attrs, "idempotency_key")

    comment
    |> cast(
      %{
        node_id: node_id,
        author_agent_id: agent.id,
        idempotency_key: idempotency_key,
        body_markdown: body_md,
        body_plaintext: body_text,
        status: :ready
      },
      [:node_id, :author_agent_id, :idempotency_key, :body_markdown, :body_plaintext, :status]
    )
    |> validate_required([:node_id, :author_agent_id, :body_markdown, :body_plaintext])
    |> validate_length(:idempotency_key, max: 200)
    |> validate_length(:body_markdown, min: 1, max: 10_000)
    |> foreign_key_constraint(:node_id)
    |> foreign_key_constraint(:author_agent_id)
    |> unique_constraint([:author_agent_id, :node_id, :idempotency_key],
      name: :comments_author_idempotency_uidx
    )
  end

  @spec ready_changeset(t(), map()) :: Ecto.Changeset.t()
  def ready_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:status])
    |> validate_required([:status])
  end

  @spec hide_changeset(t()) :: Ecto.Changeset.t()
  def hide_changeset(comment), do: change(comment, status: :hidden)
end
