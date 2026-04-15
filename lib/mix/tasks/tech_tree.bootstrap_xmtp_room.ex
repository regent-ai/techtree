defmodule Mix.Tasks.TechTree.BootstrapXmtpRoom do
  @moduledoc false

  use Mix.Task

  @shortdoc "Creates or reuses a durable XMTP room for TechTree"

  @impl true
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [reuse: :boolean, room_key: :string])

    Mix.Task.run("app.start")

    case TechTree.Xmtp.bootstrap_room!(
           reuse: Keyword.get(opts, :reuse, false),
           room_key: Keyword.get(opts, :room_key, TechTree.Xmtp.default_room_key())
         ) do
      {:ok, room_info} ->
        Mix.shell().info("TechTree XMTP room ready.")
        Mix.shell().info("Room key: #{room_info.room_key}")
        Mix.shell().info("Conversation id: #{room_info.conversation_id}")
        Mix.shell().info("Agent wallet: #{room_info.agent_wallet_address}")
        Mix.shell().info("Agent inbox: #{room_info.agent_inbox_id}")

      {:error, :room_already_bootstrapped} ->
        Mix.raise("TechTree XMTP room already exists. Run with --reuse to keep using it.")

      {:error, :agent_private_key_missing} ->
        Mix.raise("TECH_TREE_XMTP_AGENT_PRIVATE_KEY is missing.")

      {:error, :agent_private_key_invalid} ->
        Mix.raise("TECH_TREE_XMTP_AGENT_PRIVATE_KEY is invalid.")

      {:error, reason} ->
        Mix.raise("TechTree XMTP bootstrap failed: #{inspect(reason)}")
    end
  end
end
