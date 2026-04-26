defmodule TechTree.PublicChat do
  @moduledoc false

  alias TechTree.Accounts.HumanUser
  alias TechTree.Xmtp

  @room_key "public-chatbox"

  @spec subscribe() :: :ok
  def subscribe, do: Xmtp.subscribe(@room_key)

  @spec room_panel(HumanUser.t() | nil) :: map()
  def room_panel(current_human \\ nil) do
    case Xmtp.room_panel(current_human, @room_key) do
      {:ok, panel} -> panel
      {:error, reason} -> unavailable_panel(current_human, reason)
    end
  end

  @spec request_join(HumanUser.t() | nil) ::
          {:ok, map()} | {:needs_signature, map()} | {:error, atom()}
  def request_join(nil), do: {:error, :wallet_required}

  def request_join(%HumanUser{} = current_human) do
    Xmtp.request_join(current_human, @room_key)
  end

  @spec complete_join_signature(HumanUser.t() | nil, String.t(), String.t()) ::
          {:ok, map()} | {:error, atom()}
  def complete_join_signature(nil, _request_id, _signature), do: {:error, :wallet_required}

  def complete_join_signature(%HumanUser{} = current_human, request_id, signature) do
    Xmtp.complete_join_signature(current_human, request_id, signature, @room_key)
  end

  @spec send_message(HumanUser.t() | nil, String.t() | nil) :: {:ok, map()} | {:error, atom()}
  def send_message(nil, _body), do: {:error, :wallet_required}

  def send_message(%HumanUser{} = current_human, body) do
    Xmtp.send_message(current_human, body, @room_key)
  end

  @spec heartbeat(HumanUser.t() | nil) :: :ok
  def heartbeat(nil), do: :ok

  def heartbeat(%HumanUser{} = current_human) do
    :ok = Xmtp.heartbeat(current_human, @room_key)
  end

  @spec split_messages(map()) :: %{human: list(), agent: list()}
  def split_messages(%{messages: messages}) do
    messages
    |> Enum.map(&Map.put_new(&1, :tone, "muted"))
    |> Enum.reduce(%{human: [], agent: []}, fn message, acc ->
      if message.sender_kind == :agent do
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
  def reason_message(:room_unavailable), do: "This room is not open yet."
  def reason_message(:message_required), do: "Write a message before you send it."

  def reason_message(:message_too_long),
    do: "Keep the message shorter so the room stays readable."

  def reason_message(:join_required), do: "Join the room before you post."
  def reason_message(:kicked), do: "This wallet was removed from the room."
  def reason_message(:join_not_allowed), do: "This wallet cannot join this room."

  def reason_message(:signature_request_missing),
    do: "Start joining again, then sign the new request."

  def reason_message(_reason), do: "This room is not open yet."

  defp unavailable_panel(current_human, reason) do
    %{
      room_key: @room_key,
      room_name: "TechTree Public Room",
      room_id: nil,
      connected_wallet: connected_wallet(current_human),
      ready?: false,
      joined?: false,
      can_join?: false,
      can_send?: false,
      moderator?: false,
      membership_state: :view_only,
      status: reason_message(reason),
      pending_signature_request_id: nil,
      member_count: 0,
      active_member_count: 0,
      seat_count: 200,
      seats_remaining: 200,
      messages: []
    }
  end

  defp connected_wallet(%HumanUser{wallet_address: wallet}) when is_binary(wallet), do: wallet
  defp connected_wallet(_current_human), do: nil
end
