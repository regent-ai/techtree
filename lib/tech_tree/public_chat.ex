defmodule TechTree.PublicChat do
  @moduledoc false

  alias TechTree.Accounts.HumanUser
  alias TechTree.PublicEvents
  alias TechTree.XMTPMirror
  alias TechTree.XMTPMirror.Rooms

  @room_key "public-chatbox"

  @spec subscribe() :: :ok
  def subscribe, do: PublicEvents.subscribe()

  @spec room_panel(HumanUser.t() | nil) :: map()
  def room_panel(current_human \\ nil) do
    membership = membership_for(current_human)
    room_key = panel_room_key(membership)
    room = XMTPMirror.get_room_by_key(room_key)
    messages = XMTPMirror.list_public_messages(%{"room_key" => room_key, "limit" => "50"})
    member_count = member_count(room_key)
    seat_count = Rooms.room_capacity(room)

    %{
      room_key: room_key,
      room_name: room_name(room),
      room_id: room && room.id,
      connected_wallet: connected_wallet(current_human),
      ready?: not is_nil(room),
      joined?: membership.state == "joined",
      can_join?: can_join?(current_human, room, membership, member_count, seat_count),
      can_send?: membership.state == "joined",
      moderator?: false,
      membership_state: membership_state(membership, room, member_count, seat_count),
      status: panel_status(current_human, room, membership, member_count, seat_count),
      member_count: member_count,
      active_member_count: member_count,
      seat_count: seat_count,
      seats_remaining: max(seat_count - member_count, 0),
      rooms: Rooms.list_shards(),
      messages: messages
    }
  end

  @spec request_join(HumanUser.t() | nil) ::
          {:ok, map()} | {:error, atom()}
  def request_join(nil), do: {:error, :wallet_required}

  def request_join(%HumanUser{} = current_human) do
    if membership_for(current_human).state in ["joined", "join_pending", "leave_pending"] do
      {:ok, room_panel(current_human)}
    else
      case XMTPMirror.request_join(current_human, %{}) do
        {:ok, _result} -> {:ok, room_panel(current_human)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec send_message(HumanUser.t() | nil, String.t() | nil) :: {:ok, map()} | {:error, atom()}
  def send_message(nil, _body), do: {:error, :wallet_required}

  def send_message(%HumanUser{} = current_human, body) do
    room_key = active_room_key(current_human)

    case XMTPMirror.create_human_message(current_human, %{"room_key" => room_key, "body" => body}) do
      {:ok, _message} -> {:ok, room_panel(current_human)}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, message_error(changeset)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec heartbeat(HumanUser.t() | nil) :: :ok
  def heartbeat(nil), do: :ok

  def heartbeat(%HumanUser{} = current_human) do
    _ =
      XMTPMirror.heartbeat_presence(current_human, %{"room_key" => active_room_key(current_human)})

    :ok
  end

  @spec split_messages(map()) :: %{human: list(), agent: list()}
  def split_messages(%{messages: messages}) do
    messages
    |> Enum.map(&Map.put_new(&1, :tone, "muted"))
    |> Enum.reduce(%{human: [], agent: []}, fn message, acc ->
      if Map.get(message, :sender_type) == :agent do
        %{acc | agent: [message | acc.agent]}
      else
        %{acc | human: [message | acc.human]}
      end
    end)
    |> Map.update!(:human, &Enum.reverse/1)
    |> Map.update!(:agent, &Enum.reverse/1)
  end

  def split_messages(_panel), do: %{human: [], agent: []}

  @spec reason_message(atom()) :: String.t()
  def reason_message(:wallet_required), do: "Sign in before you join this room."
  def reason_message(:room_full), do: "This room is full right now. You can still read along."
  def reason_message(:already_in_room), do: "Leave your current room before joining another one."
  def reason_message(:room_unavailable), do: "This room is not open yet."
  def reason_message(:message_required), do: "Write a message before you send it."

  def reason_message(:message_too_long),
    do: "Keep the message shorter so the room stays readable."

  def reason_message(:join_required), do: "Join the room before you post."
  def reason_message(:xmtp_membership_required), do: "Join the room before you post."
  def reason_message(:xmtp_identity_required), do: "Finish room setup before you join."
  def reason_message(:kicked), do: "This wallet was removed from the room."
  def reason_message(:human_banned), do: "This wallet cannot join this room."
  def reason_message(:join_not_allowed), do: "This wallet cannot join this room."

  def reason_message(_reason), do: "This room is not open yet."

  defp membership_for(%HumanUser{} = human), do: XMTPMirror.membership_for(human)

  defp membership_for(_current_human) do
    %{
      room_key: @room_key,
      room_present: not is_nil(XMTPMirror.get_room_by_key(@room_key)),
      state: "view_only"
    }
  end

  defp can_join?(nil, _room, _membership, _member_count, _seat_count), do: false
  defp can_join?(_human, nil, _membership, _member_count, _seat_count), do: false
  defp can_join?(_human, _room, %{state: "joined"}, _member_count, _seat_count), do: false
  defp can_join?(_human, _room, %{state: "setup_required"}, _member_count, _seat_count), do: false

  defp can_join?(_human, _room, _membership, member_count, seat_count),
    do: member_count < seat_count

  defp member_count(room_key) do
    room_key
    |> XMTPMirror.get_room_by_key()
    |> case do
      nil -> 0
      room -> Rooms.active_member_count(room.id)
    end
  end

  defp membership_state(_membership, nil, _member_count, _seat_count), do: :room_unavailable
  defp membership_state(%{state: "joined"}, _room, _member_count, _seat_count), do: :joined

  defp membership_state(%{state: "join_pending"}, _room, _member_count, _seat_count),
    do: :join_pending

  defp membership_state(%{state: "leave_pending"}, _room, _member_count, _seat_count),
    do: :leave_pending

  defp membership_state(%{state: "setup_required"}, _room, _member_count, _seat_count),
    do: :setup_required

  defp membership_state(_membership, _room, member_count, seat_count)
       when member_count >= seat_count,
       do: :full

  defp membership_state(_membership, _room, _member_count, _seat_count), do: :view_only

  defp panel_status(nil, _room, _membership, _member_count, _seat_count),
    do: "Read along now. Sign in before you post."

  defp panel_status(_human, nil, _membership, _member_count, _seat_count),
    do: reason_message(:room_unavailable)

  defp panel_status(_human, _room, %{state: "joined"}, _member_count, _seat_count),
    do: "You can post in the public room."

  defp panel_status(_human, _room, %{state: "setup_required"}, _member_count, _seat_count),
    do: reason_message(:xmtp_identity_required)

  defp panel_status(_human, _room, %{state: "join_pending"}, _member_count, _seat_count),
    do: "Your room seat is being prepared."

  defp panel_status(_human, _room, _membership, member_count, seat_count)
       when member_count >= seat_count,
       do: reason_message(:room_full)

  defp panel_status(_human, _room, _membership, _member_count, _seat_count),
    do: "Sign in, then join when you want to post."

  defp message_error(%Ecto.Changeset{} = changeset) do
    cond do
      changeset_error?(changeset, :body, "can't be blank") -> :message_required
      changeset_error?(changeset, :body, "should be at most") -> :message_too_long
      true -> :room_unavailable
    end
  end

  defp changeset_error?(%Ecto.Changeset{errors: errors}, field, fragment) do
    Enum.any?(errors, fn
      {^field, {message, _opts}} -> String.contains?(message, fragment)
      _error -> false
    end)
  end

  defp room_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp room_name(_room), do: "TechTree Public Room"

  defp connected_wallet(%HumanUser{wallet_address: wallet}) when is_binary(wallet), do: wallet
  defp connected_wallet(_current_human), do: nil

  defp panel_room_key(%{room_key: room_key}) when is_binary(room_key) and room_key != "",
    do: room_key

  defp panel_room_key(_membership), do: @room_key

  defp active_room_key(%HumanUser{} = human) do
    case membership_for(human) do
      %{state: "joined", room_key: room_key} when is_binary(room_key) and room_key != "" ->
        room_key

      _membership ->
        @room_key
    end
  end
end
