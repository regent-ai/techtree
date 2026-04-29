defmodule TechTreeWeb.Platform.ModerationPresenter do
  @moduledoc false

  alias TechTree.Chatbox.Message

  @spec author_ref(Message.t()) :: integer() | nil
  def author_ref(%Message{author_kind: :human, author_human_id: id}), do: id
  def author_ref(%Message{author_kind: :agent, author_agent_id: id}), do: id
  def author_ref(_message), do: nil

  @spec author_ban_action(Message.t()) :: String.t()
  def author_ban_action(%Message{author_kind: :agent}), do: "ban_agent"
  def author_ban_action(_message), do: "ban_human"

  @spec author_restore_action(Message.t()) :: String.t()
  def author_restore_action(%Message{author_kind: :agent}), do: "unban_agent"
  def author_restore_action(_message), do: "unban_human"

  @spec author_active?(Message.t()) :: boolean()
  def author_active?(%Message{author_kind: :human, author_human: %{role: role}}),
    do: role != "banned"

  def author_active?(%Message{author_kind: :agent, author_agent: %{status: status}}),
    do: status == "active"

  def author_active?(_message), do: false

  @spec author_status(Message.t()) :: String.t()
  def author_status(%Message{author_kind: :human, author_human: %{role: role}}),
    do: role || "unknown"

  def author_status(%Message{author_kind: :agent, author_agent: %{status: status}}),
    do: status || "unknown"

  def author_status(_message), do: "unknown"

  @spec message_visibility(Message.t()) :: String.t()
  def message_visibility(%Message{moderation_state: state}) when is_binary(state), do: state
  def message_visibility(_message), do: "unknown"

  @spec message_author_label(Message.t()) :: String.t()
  def message_author_label(%Message{
        author_kind: :human,
        author_human: %{display_name: display_name}
      })
      when is_binary(display_name) and display_name != "",
      do: display_name

  def message_author_label(%Message{author_kind: :agent, author_agent: %{label: label}})
      when is_binary(label) and label != "",
      do: label

  def message_author_label(%Message{
        author_kind: :human,
        author_human: %{wallet_address: wallet}
      })
      when is_binary(wallet),
      do: compact_wallet(wallet)

  def message_author_label(%Message{
        author_kind: :agent,
        author_agent: %{wallet_address: wallet}
      })
      when is_binary(wallet),
      do: compact_wallet(wallet)

  def message_author_label(%Message{author_kind: :human, author_human_id: id}), do: "human ##{id}"
  def message_author_label(%Message{author_kind: :agent, author_agent_id: id}), do: "agent ##{id}"
  def message_author_label(_message), do: "unknown author"

  @spec message_author_meta(Message.t()) :: String.t()
  def message_author_meta(%Message{author_kind: :human} = message) do
    "human #{compact_wallet(wallet_for(message))}"
  end

  def message_author_meta(%Message{author_kind: :agent} = message) do
    "agent #{compact_wallet(wallet_for(message))}"
  end

  def message_author_meta(_message), do: "wallet unavailable"

  @spec badge_class(String.t()) :: [String.t()]
  def badge_class(value) do
    [
      "inline-flex rounded-full border px-3 py-1 text-[0.66rem] uppercase tracking-[0.22em]",
      badge_tone(value)
    ]
  end

  @spec format_timestamp(DateTime.t() | term()) :: String.t()
  def format_timestamp(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")
  def format_timestamp(_value), do: "-"

  @spec present?(term()) :: boolean()
  def present?(value) when is_binary(value), do: String.trim(value) != ""
  def present?(_value), do: false

  defp wallet_for(%Message{author_kind: :human, author_human: %{wallet_address: wallet}}),
    do: wallet

  defp wallet_for(%Message{author_kind: :agent, author_agent: %{wallet_address: wallet}}),
    do: wallet

  defp wallet_for(_message), do: nil

  defp compact_wallet(nil), do: "wallet unavailable"

  defp compact_wallet(wallet) when is_binary(wallet) and byte_size(wallet) > 12 do
    String.slice(wallet, 0, 6) <> "..." <> String.slice(wallet, -4, 4)
  end

  defp compact_wallet(wallet) when is_binary(wallet), do: wallet

  defp badge_tone(value) when value in ["visible", "active", "user"] do
    "border-emerald-400/40 bg-emerald-500/12 text-emerald-700 dark:text-emerald-300"
  end

  defp badge_tone(value) when value in ["hidden", "banned", "inactive"] do
    "border-rose-400/40 bg-rose-500/12 text-rose-700 dark:text-rose-300"
  end

  defp badge_tone(_value) do
    "border-amber-400/40 bg-amber-500/12 text-amber-700 dark:text-amber-300"
  end
end
