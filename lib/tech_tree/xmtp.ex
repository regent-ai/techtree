defmodule TechTree.Xmtp do
  @moduledoc false

  alias Xmtp.Principal
  alias TechTree.Accounts.HumanUser
  alias TechTree.Agents.AgentIdentity
  alias TechTree.XmtpIdentity

  @manager __MODULE__.Manager

  def child_spec(opts \\ []) do
    Xmtp.child_spec(
      Keyword.merge(opts,
        name: @manager,
        repo: TechTree.Repo,
        pubsub: TechTree.PubSub,
        rooms: {:mfa, __MODULE__, :rooms, []}
      )
    )
  end

  def rooms do
    :tech_tree
    |> Application.get_env(__MODULE__, [])
    |> Keyword.fetch!(:rooms)
  end

  def default_room_key do
    rooms()
    |> List.first()
    |> Map.fetch!(:key)
  end

  def topic(room_key \\ default_room_key()), do: Xmtp.topic(@manager, room_key)

  def subscribe(room_key \\ default_room_key()) do
    Xmtp.subscribe(@manager, room_key)
  end

  def room_panel(principal, room_key \\ default_room_key(), claims \\ %{}) do
    Xmtp.public_room_panel(@manager, room_key, normalize_principal(principal), claims)
  end

  def request_join(principal, room_key \\ default_room_key(), claims \\ %{}) do
    Xmtp.request_join(@manager, room_key, normalize_principal(principal), claims)
  end

  def complete_join_signature(
        principal,
        request_id,
        signature,
        room_key \\ default_room_key(),
        claims \\ %{}
      ) do
    Xmtp.complete_join_signature(
      @manager,
      room_key,
      normalize_principal(principal),
      request_id,
      signature,
      claims
    )
  end

  def send_message(principal, body, room_key \\ default_room_key()) do
    Xmtp.send_public_message(@manager, room_key, normalize_principal(principal), body)
  end

  def heartbeat(principal, room_key \\ default_room_key()) do
    Xmtp.heartbeat(@manager, room_key, normalize_principal(principal))
  end

  def invite_user(actor, target, room_key \\ default_room_key(), claims \\ %{}) do
    Xmtp.invite_user(
      @manager,
      room_key,
      normalize_actor(actor),
      normalize_target(target),
      claims
    )
  end

  def kick_user(actor, target, room_key \\ default_room_key()) do
    Xmtp.kick_user(@manager, room_key, normalize_actor(actor), normalize_target(target))
  end

  def moderator_delete_message(actor, message_id, room_key \\ default_room_key()) do
    Xmtp.moderator_delete_message(
      @manager,
      room_key,
      normalize_actor(actor),
      message_id
    )
  end

  def bootstrap_room!(opts \\ []) do
    room_key = Keyword.get(opts, :room_key, default_room_key())
    Xmtp.bootstrap_room!(@manager, room_key, opts)
  end

  def principal_for_agent_wallet(wallet_address, label \\ nil) do
    Principal.agent(%{wallet_address: wallet_address, display_name: label})
  end

  defp normalize_actor(:system), do: :system
  defp normalize_actor(actor), do: normalize_principal(actor)

  defp normalize_target(target) when is_binary(target), do: target
  defp normalize_target(target), do: normalize_principal(target)

  defp normalize_principal(%HumanUser{} = human) do
    Principal.human(%{
      id: human.id,
      wallet_address: human.wallet_address,
      inbox_id: principal_inbox_id(human),
      display_name: human.display_name
    })
  end

  defp normalize_principal(%AgentIdentity{} = agent) do
    Principal.agent(%{
      id: agent.id,
      wallet_address: agent.wallet_address,
      display_name: agent.label
    })
  end

  defp normalize_principal(%{} = attrs), do: Principal.from(attrs)
  defp normalize_principal(nil), do: nil

  defp principal_inbox_id(%HumanUser{} = human) do
    case XmtpIdentity.ready_inbox_id(human) do
      {:ok, inbox_id} -> inbox_id
      {:error, _reason} -> nil
    end
  end
end
