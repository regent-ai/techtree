defmodule TechTree.ApplicationRuntimeConfigTest do
  use ExUnit.Case, async: false

  describe "validate_siwa_runtime_config!/2" do
    test "allows standard SIWA config in non-test environments" do
      assert :ok =
               TechTree.Application.validate_siwa_runtime_config!(
                 :prod,
                 internal_url: "http://siwa-sidecar:4100",
                 shared_secret: "secret"
               )
    end

    test "raises in prod when internal_url is missing" do
      assert_raise RuntimeError,
                   ~r/internal_url must be configured in :prod/,
                   fn ->
                     TechTree.Application.validate_siwa_runtime_config!(
                       :prod,
                       shared_secret: "secret"
                     )
                   end
    end

    test "raises in prod when shared_secret is missing" do
      assert_raise RuntimeError,
                   ~r/shared_secret must be configured in :prod/,
                   fn ->
                     TechTree.Application.validate_siwa_runtime_config!(
                       :prod,
                       internal_url: "http://siwa-sidecar:4100"
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

  describe "dragonfly rate-limit policy" do
    setup do
      original_backend = Application.get_env(:tech_tree, TechTree.RateLimit, [])
      original_enabled = Application.get_env(:tech_tree, :dragonfly_enabled)
      original_name = Application.get_env(:tech_tree, :dragonfly_name)

      on_exit(fn ->
        restore_application_env(:tech_tree, TechTree.RateLimit, original_backend)
        restore_application_env(:tech_tree, :dragonfly_enabled, original_enabled)
        restore_application_env(:tech_tree, :dragonfly_name, original_name)
        TechTree.RateLimit.reset!()
      end)

      :ok
    end

    test "reports intentional local-only mode without degradation" do
      Application.put_env(:tech_tree, :dragonfly_enabled, true)
      Application.put_env(:tech_tree, TechTree.RateLimit, backend: :local)

      assert %{
               configured_backend: :local,
               effective_backend: :local,
               dragonfly_enabled: true,
               dragonfly_reachable: nil,
               degraded: false,
               last_error: nil
             } = TechTree.RateLimit.status()
    end

    test "local fallback state survives across request processes" do
      Application.put_env(:tech_tree, :dragonfly_enabled, true)
      Application.put_env(:tech_tree, TechTree.RateLimit, backend: :local)

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

    test "fails closed and records degraded state when dragonfly is unavailable" do
      unavailable_name = :"dragonfly_unavailable_#{System.unique_integer([:positive])}"

      Application.put_env(:tech_tree, :dragonfly_enabled, true)
      Application.put_env(:tech_tree, :dragonfly_name, unavailable_name)
      Application.put_env(:tech_tree, TechTree.RateLimit, backend: :dragonfly)

      assert {:error, %{code: :rate_limited, retry_after_ms: retry_after_ms}} =
               TechTree.RateLimit.allow_chatbox_message(
                 actor_scope: "actor:#{System.unique_integer([:positive])}",
                 principal_scope: "principal:#{System.unique_integer([:positive])}",
                 ip_scope: "127.0.0.1",
                 message_body: "dragonfly degraded fail closed"
               )

      assert retry_after_ms > 0

      assert %{
               configured_backend: :dragonfly,
               effective_backend: :dragonfly,
               dragonfly_enabled: true,
               dragonfly_reachable: false,
               degraded: true,
               last_error: last_error,
               last_degraded_at_ms: last_degraded_at_ms
             } = TechTree.RateLimit.status()

      assert is_binary(last_error)
      assert is_integer(last_degraded_at_ms)
    end
  end

  defp restore_application_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_application_env(app, key, value), do: Application.put_env(app, key, value)
end
