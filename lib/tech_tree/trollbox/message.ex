defmodule TechTree.Trollbox.Message do
  @moduledoc false

  use TechTree.Schema

  @author_kinds [:human, :agent]

  @type t :: %__MODULE__{
          id: integer() | nil,
          room_id: String.t() | nil,
          author_kind: :human | :agent | nil,
          author_scope: String.t() | nil,
          author_human_id: integer() | nil,
          author_agent_id: integer() | nil,
          author_transport_id: String.t() | nil,
          author_display_name_snapshot: String.t() | nil,
          author_label_snapshot: String.t() | nil,
          author_wallet_address_snapshot: String.t() | nil,
          client_message_id: String.t() | nil,
          body: String.t() | nil,
          reply_to_message_id: integer() | nil,
          reply_to_transport_msg_id: String.t() | nil,
          reactions: map(),
          moderation_state: String.t() | nil,
          transport_msg_id: String.t() | nil,
          transport_topic: String.t() | nil,
          origin_peer_id: String.t() | nil,
          origin_node_id: String.t() | nil,
          transport_payload: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "trollbox_messages" do
    field :room_id, :string, default: "global"
    field :author_kind, Ecto.Enum, values: @author_kinds
    field :author_scope, :string
    field :author_transport_id, :string
    field :author_display_name_snapshot, :string
    field :author_label_snapshot, :string
    field :author_wallet_address_snapshot, :string
    field :client_message_id, :string
    field :body, :string
    field :reply_to_transport_msg_id, :string
    field :reactions, :map, default: %{}
    field :moderation_state, :string, default: "visible"
    field :transport_msg_id, :string
    field :transport_topic, :string
    field :origin_peer_id, :string
    field :origin_node_id, :string
    field :transport_payload, :map, default: %{}

    belongs_to :author_human, TechTree.Accounts.HumanUser
    belongs_to :author_agent, TechTree.Agents.AgentIdentity
    belongs_to :reply_to_message, __MODULE__

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :room_id,
      :author_kind,
      :author_scope,
      :author_human_id,
      :author_agent_id,
      :author_transport_id,
      :author_display_name_snapshot,
      :author_label_snapshot,
      :author_wallet_address_snapshot,
      :client_message_id,
      :body,
      :reply_to_message_id,
      :reply_to_transport_msg_id,
      :reactions,
      :moderation_state,
      :transport_msg_id,
      :transport_topic,
      :origin_peer_id,
      :origin_node_id,
      :transport_payload,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :room_id,
      :author_kind,
      :author_scope,
      :body,
      :transport_msg_id,
      :transport_topic
    ])
    |> validate_length(:room_id, max: 128)
    |> validate_length(:author_scope, max: 64)
    |> validate_length(:author_transport_id, max: 128)
    |> validate_length(:author_display_name_snapshot, max: 160)
    |> validate_length(:author_label_snapshot, max: 160)
    |> validate_length(:author_wallet_address_snapshot, max: 128)
    |> validate_length(:client_message_id, max: 128)
    |> validate_length(:body, max: 2_000)
    |> validate_length(:reply_to_transport_msg_id, max: 160)
    |> validate_length(:transport_msg_id, max: 160)
    |> validate_length(:transport_topic, max: 160)
    |> validate_length(:origin_peer_id, max: 160)
    |> validate_length(:origin_node_id, max: 160)
    |> foreign_key_constraint(:author_human_id)
    |> foreign_key_constraint(:author_agent_id)
    |> foreign_key_constraint(:reply_to_message_id)
    |> check_constraint(:author_kind, name: :trollbox_messages_author_kind_check)
    |> check_constraint(:author_human_id, name: :trollbox_messages_author_ref_check)
    |> unique_constraint(:transport_msg_id, name: :trollbox_messages_transport_msg_id_uidx)
    |> unique_constraint(:client_message_id,
      name: :trollbox_messages_author_scope_client_message_id_uidx
    )
  end
end
