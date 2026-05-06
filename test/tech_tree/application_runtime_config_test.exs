defmodule TechTree.ApplicationRuntimeConfigTest do
  use ExUnit.Case, async: false

  describe "validate_siwa_runtime_config!/2" do
    test "allows standard SIWA config in non-test environments" do
      assert :ok =
               TechTree.Application.validate_siwa_runtime_config!(
                 :prod,
                 internal_url: "http://siwa-server:4100"
               )
    end

    test "raises in prod when internal_url is missing" do
      assert_raise RuntimeError,
                   ~r/internal_url must be configured in :prod/,
                   fn ->
                     TechTree.Application.validate_siwa_runtime_config!(
                       :prod,
                       []
                     )
                   end
    end

    test "raises when :siwa configuration is not a keyword list" do
      assert_raise ArgumentError,
                   ~r/expected :siwa to be a keyword list/,
                   fn ->
                     TechTree.Application.validate_siwa_runtime_config!(:test, %{
                       enabled: true
                     })
                   end
    end
  end

  describe "local cache rate-limit policy" do
    setup do
      original_backend = Application.get_env(:tech_tree, TechTree.RateLimit, [])

      on_exit(fn ->
        restore_application_env(:tech_tree, TechTree.RateLimit, original_backend)
        TechTree.RateLimit.reset!()
      end)

      :ok
    end

    test "reports local cache mode without degradation" do
      Application.put_env(:tech_tree, TechTree.RateLimit, backend: :cachex)

      assert %{
               configured_backend: :cachex,
               effective_backend: :cachex,
               cache_ready: true,
               degraded: false,
               last_error: nil
             } = TechTree.RateLimit.status()
    end

    test "local cache state survives across request processes" do
      Application.put_env(:tech_tree, TechTree.RateLimit, backend: :cachex)

      message_opts = [
        actor_scope: "human:cross-process",
        principal_scope: "privy:cross-process",
        ip_scope: "127.0.0.1",
        message_body: "cross process duplicate"
      ]

      assert :ok =
               Task.async(fn -> TechTree.RateLimit.allow_chatbox_message(message_opts) end)
               |> Task.await()

      assert {:error, %{code: :duplicate_message, retry_after_ms: retry_after_ms}} =
               Task.async(fn -> TechTree.RateLimit.allow_chatbox_message(message_opts) end)
               |> Task.await()

      assert retry_after_ms > 0
    end
  end

  defp restore_application_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_application_env(app, key, value), do: Application.put_env(app, key, value)
end
