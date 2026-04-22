defmodule TechTree.XMTPMirror do
  @moduledoc false

  alias TechTree.Accounts.HumanUser
  alias TechTree.XMTPMirror.Messages
  alias TechTree.XMTPMirror.Membership
  alias TechTree.XMTPMirror.Rooms
  alias TechTree.XMTPMirror.XmtpMembershipCommand
  alias TechTree.XMTPMirror.XmtpMessage
  alias TechTree.XMTPMirror.XmtpRoom

  @type room_admin_action_error ::
          :human_not_found | :human_banned | :room_not_found | :xmtp_identity_required

  @type room_admin_action_status ::
          :enqueued
          | :already_joined
          | :already_pending_join
          | :already_not_joined
          | :already_pending_removal

  @spec ensure_room(map()) :: {:ok, XmtpRoom.t()} | {:error, Ecto.Changeset.t()}
  def ensure_room(attrs) when is_map(attrs), do: Rooms.ensure_room(attrs)

  @spec get_room_by_key(String.t() | nil) :: XmtpRoom.t() | nil
  def get_room_by_key(room_key), do: Rooms.get_room_by_key(room_key)

  @spec ingest_message(map()) ::
          {:ok, XmtpMessage.t()}
          | {:error,
             :room_not_found | :invalid_reply_to_message | :invalid_reactions | Ecto.Changeset.t()}
  def ingest_message(attrs) when is_map(attrs), do: Messages.ingest_message(attrs)

  @spec lease_next_command(String.t() | integer() | nil) :: XmtpMembershipCommand.t() | nil
  def lease_next_command(room_key_or_id), do: Membership.lease_next_command(room_key_or_id)

  @spec resolve_command(integer() | String.t(), map()) ::
          :ok | {:error, :invalid_resolution_status}
  def resolve_command(command_id, attrs), do: Membership.resolve_command(command_id, attrs)

  @spec request_join(HumanUser.t(), map()) ::
          {:ok, map()} | {:error, :room_not_found | :human_banned | :xmtp_identity_required}
  def request_join(human, attrs \\ %{})

  def request_join(%HumanUser{role: "banned"}, _attrs), do: {:error, :human_banned}

  def request_join(%HumanUser{} = human, attrs) when is_map(attrs),
    do: Membership.request_join(human, attrs)

  @spec create_human_message(HumanUser.t(), map()) ::
          {:ok, XmtpMessage.t()}
          | {:error,
             :human_banned | :room_not_found | :xmtp_identity_required | Ecto.Changeset.t()}
  def create_human_message(%HumanUser{role: "banned"}, _attrs), do: {:error, :human_banned}

  def create_human_message(%HumanUser{} = human, attrs) when is_map(attrs),
    do: Messages.create_human_message(human, attrs)

  @spec list_public_messages(map()) :: [XmtpMessage.t()]
  def list_public_messages(attrs \\ %{}) when is_map(attrs),
    do: Messages.list_public_messages(attrs)

  @spec heartbeat_presence(HumanUser.t(), map()) ::
          {:ok, map()}
          | {:error,
             :room_not_found | :human_banned | :xmtp_identity_required | Ecto.Changeset.t()}
  def heartbeat_presence(human, attrs \\ %{})

  def heartbeat_presence(%HumanUser{role: "banned"}, _attrs), do: {:error, :human_banned}

  def heartbeat_presence(%HumanUser{} = human, attrs) when is_map(attrs) do
    Membership.heartbeat_presence(human, attrs)
  end

  @spec membership_for(HumanUser.t()) :: map()
  def membership_for(%HumanUser{} = human), do: Membership.membership_for(human)

  @spec add_human_to_canonical_room(integer() | String.t()) ::
          {:ok, room_admin_action_status()} | {:error, room_admin_action_error()}
  def add_human_to_canonical_room(human_id) when is_integer(human_id) or is_binary(human_id) do
    Membership.add_human_to_canonical_room(human_id)
  end

  @spec remove_human_from_canonical_room(integer() | String.t()) ::
          {:ok, room_admin_action_status()} | {:error, room_admin_action_error()}
  def remove_human_from_canonical_room(human_id)
      when is_integer(human_id) or is_binary(human_id) do
    Membership.remove_human_from_canonical_room(human_id)
  end

  @spec remove_human_from_canonical_room(HumanUser.t()) ::
          {:ok, room_admin_action_status()} | {:error, room_admin_action_error()}
  def remove_human_from_canonical_room(%HumanUser{} = human) do
    Membership.remove_human_from_canonical_room(human)
  end

  @spec best_effort_remove_human_from_canonical_room(integer() | String.t()) :: :ok
  def best_effort_remove_human_from_canonical_room(human_id)
      when is_integer(human_id) or is_binary(human_id) do
    Membership.best_effort_remove_human_from_canonical_room(human_id)
  end

  @spec list_shards() :: [map()]
  def list_shards, do: Rooms.list_shards()
end
