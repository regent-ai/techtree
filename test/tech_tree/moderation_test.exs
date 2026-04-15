defmodule TechTree.ModerationTest do
  use TechTree.DataCase, async: false

  import TechTree.PhaseDApiSupport, only: [create_chatbox_message!: 2]

  alias TechTree.{Accounts, Moderation}

  test "chatbox_dashboard keeps the selected message and loads that author's history" do
    first_author = create_human!("moderation-dashboard-first")
    second_author = create_human!("moderation-dashboard-second")

    first_message = create_chatbox_message!(first_author, %{body: "first author message"})
    second_message = create_chatbox_message!(second_author, %{body: "second author message"})
    second_history = create_chatbox_message!(second_author, %{body: "second author history"})

    dashboard = Moderation.chatbox_dashboard(%{}, second_message.id)

    assert Enum.any?(dashboard.messages, &(&1.id == first_message.id))
    assert dashboard.selected_message.id == second_message.id
    assert dashboard.selected_message_id == second_message.id
    assert Enum.map(dashboard.actor_history, & &1.id) == [second_history.id, second_message.id]
  end

  defp create_human!(prefix) do
    unique = System.unique_integer([:positive])

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("#{prefix}-#{unique}", %{
        "wallet_address" => "0x#{prefix}-wallet-#{unique}",
        "display_name" => "#{prefix}-#{unique}",
        "role" => "user"
      })

    human
  end
end
