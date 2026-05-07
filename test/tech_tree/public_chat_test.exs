defmodule TechTree.PublicChatTest do
  use TechTree.DataCase, async: false

  import TechTree.PhaseDApiSupport,
    only: [
      create_canonical_room!: 0,
      create_human!: 1,
      create_human!: 2,
      create_visible_message!: 2,
      join_public_room!: 2
    ]

  alias TechTree.{PublicChat, PublicEvents}
  alias TechTree.Repo
  alias TechTree.XMTPMirror
  alias TechTree.XMTPMirror.XmtpMembershipCommand
  alias Xmtp.RoomPanel

  setup do
    previous_animata = Application.get_env(:tech_tree, :animata_holdings)
    previous_ens = Application.get_env(:tech_tree, :ens_primary_name)

    Application.put_env(:tech_tree, :animata_holdings,
      http_client: __MODULE__.AnimataHttp,
      opensea_api_key: "test-key"
    )

    Application.put_env(:tech_tree, :ens_primary_name,
      rpc_module: __MODULE__.EnsPrimaryRpc,
      rpc_url: "https://ethereum.example.invalid"
    )

    on_exit(fn ->
      restore_app_env(:tech_tree, :animata_holdings, previous_animata)
      restore_app_env(:tech_tree, :ens_primary_name, previous_ens)
    end)

    %{room: create_canonical_room!(), human: create_human!("public-chat")}
  end

  test "anonymous visitors can read the mirrored public room", %{room: room} do
    message =
      create_visible_message!(room, %{
        sender_type: :human,
        sender_label: "reader",
        body: "visible to everyone"
      })

    panel = PublicChat.room_panel(nil)

    assert %RoomPanel{} = panel
    assert panel.membership == :not_joined
    refute panel.can_join
    refute panel.can_send
    assert Enum.map(panel.messages, & &1.id) == [message.id]
  end

  test "room messages show verified ENS names and mark Animata holders", %{room: room} do
    message =
      create_visible_message!(room, %{
        sender_wallet_address: "0xabc0000000000000000000000000000000000011",
        sender_inbox_id: "inbox-ens-holder",
        sender_type: :human,
        sender_label: "stored label",
        body: "Name check."
      })

    panel = PublicChat.room_panel(nil)

    message_id = message.id

    assert [%{id: ^message_id, author: "primary-room.eth", author_tone: :animata_holder}] =
             panel.messages
  end

  test "posting requires mirror membership and broadcasts saved messages", %{
    room: room,
    human: human
  } do
    assert {:error, :xmtp_membership_required} = PublicChat.send_message(human, "before join")

    join_public_room!(room, human)
    :ok = PublicEvents.subscribe()

    assert {:ok, panel} = PublicChat.send_message(human, "after join")
    assert panel.membership == :joined
    assert panel.can_send

    assert_receive {:public_site_event,
                    %{
                      event: :xmtp_room_message,
                      room_key: "public-chatbox",
                      message: %{body: "after join"}
                    }}
  end

  test "completed join commands refresh the public room", %{room: room, human: human} do
    assert {:ok, _panel} = PublicChat.request_join(human)
    command = Repo.get_by!(XmtpMembershipCommand, room_id: room.id, human_user_id: human.id)

    :ok = PublicEvents.subscribe()

    assert :ok = XMTPMirror.resolve_command(command.id, %{"status" => "done"})

    assert_receive {:public_site_event,
                    %{
                      event: :xmtp_room_membership,
                      room_key: "public-chatbox"
                    }}

    assert PublicChat.room_panel(human).membership == :joined
  end

  test "one human cannot join two public rooms at the same time", %{room: room, human: human} do
    join_public_room!(room, human)
    suffix = System.unique_integer([:positive])

    {:ok, shard_room} =
      XMTPMirror.ensure_room(%{
        "room_key" => "public-chatbox-shard-#{suffix}",
        "xmtp_group_id" => "xmtp-public-chatbox-shard-#{suffix}",
        "name" => "Public Chatbox ##{suffix}",
        "status" => "active"
      })

    assert {:error, :already_in_room} =
             XMTPMirror.request_join(human, %{"room_key" => shard_room.room_key})
  end

  test "banned human messages stay out of public reads", %{room: room} do
    banned = create_human!("banned-reader", role: "banned")

    create_visible_message!(room, %{
      sender_wallet_address: banned.wallet_address,
      sender_inbox_id: banned.xmtp_inbox_id,
      sender_type: :human,
      body: "do not relay"
    })

    assert PublicChat.room_panel(nil).messages == []
  end

  test "banned humans cannot use public room actions", %{room: room} do
    banned = create_human!("banned-actions", role: "banned")
    join_public_room!(room, banned)

    panel = PublicChat.room_panel(banned)

    assert panel.membership == :removed
    refute panel.can_join
    refute panel.can_send
    assert panel.user_copy.primary == "This wallet cannot join this room."
  end

  defp restore_app_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_app_env(app, key, value), do: Application.put_env(app, key, value)

  defmodule AnimataHttp do
    @moduledoc false
    @behaviour TechTree.AnimataHoldings

    @impl true
    def get(url, _options) do
      if url |> URI.to_string() |> String.contains?("collection=animata") do
        {:ok, %{status: 200, body: %{"nfts" => [%{"identifier" => "7"}]}}}
      else
        {:ok, %{status: 200, body: %{"nfts" => []}}}
      end
    end
  end

  defmodule EnsPrimaryRpc do
    @moduledoc false
    @behaviour AgentEns.Internal.RPC

    @wallet "0xabc0000000000000000000000000000000000011"
    @resolver "0x226159d592e2b063810a10ebf6dcbada94ed68b8"

    @impl true
    def eth_call(_rpc_url, _to, data) do
      case data do
        "0x0178b8bf" <> _rest -> {:ok, address_word(@resolver)}
        "0x691f3431" <> _rest -> {:ok, encode_string("primary-room.eth")}
        "0xf1cb7e06" <> _rest -> {:ok, bool_word(true)}
        "0x02571be3" <> _rest -> {:ok, address_word(@wallet)}
        "0x16a25cbd" <> _rest -> {:ok, uint_word(300)}
        "0x01ffc9a7" <> rest -> {:ok, supports_interface(rest)}
        "0x3b3b57de" <> _rest -> {:ok, address_word(@wallet)}
        _other -> {:ok, uint_word(0)}
      end
    end

    defp supports_interface(rest) do
      if String.starts_with?(rest, "3b3b57de"), do: bool_word(true), else: bool_word(false)
    end

    defp address_word("0x" <> address) do
      "0x" <> String.pad_leading(String.downcase(address), 64, "0")
    end

    defp bool_word(true), do: uint_word(1)
    defp bool_word(false), do: uint_word(0)

    defp uint_word(value), do: "0x" <> String.pad_leading(Integer.to_string(value, 16), 64, "0")

    defp encode_string(value) do
      binary = :erlang.iolist_to_binary(value)
      hex = Base.encode16(binary, case: :lower)
      padding = rem(64 - rem(byte_size(hex), 64), 64)

      "0x" <>
        String.pad_leading("20", 64, "0") <>
        String.pad_leading(Integer.to_string(byte_size(binary), 16), 64, "0") <>
        hex <> String.duplicate("0", padding)
    end
  end
end
