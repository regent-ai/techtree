defmodule TechTree.InfrastructureConfigTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  test "production runtime uses pooled database URL settings" do
    runtime = File.read!(Path.join(@root, "config/runtime.exs"))

    assert runtime =~ ~s|System.get_env("DATABASE_URL")|
    refute runtime =~ "DATABASE_DIRECT_URL"
    assert runtime =~ "ssl: true"
    assert runtime =~ "prepare: :unnamed"

    assert runtime =~ ~S<System.get_env("ECTO_POOL_SIZE") || "5">
    assert runtime =~ ~s(migration_default_prefix: "techtree")
    assert runtime =~ ~s(migration_source: "schema_migrations_techtree")
  end

  test "release migrations use the direct database URL and techtree schema only" do
    release = File.read!(Path.join(@root, "lib/tech_tree/release.ex"))

    assert release =~ ~s|System.fetch_env!("DATABASE_DIRECT_URL")|
    refute release =~ ~s|System.fetch_env!("DATABASE_URL")|
    assert release =~ ~s(@schema "techtree")
    assert release =~ ~s(@migration_source "schema_migrations_techtree")
    refute release =~ ~s(@schema "platform")
    refute release =~ ~s(@schema "autolaunch")
  end

  test "production runtime requires managed env values instead of local env files" do
    runtime = File.read!(Path.join(@root, "config/runtime.exs"))

    assert runtime =~ ~S|if config_env() == :prod do|
    assert runtime =~ "System.get_env(key) || default"
    assert runtime =~ ~S|TechTree.ConfigEnvLocal.fetch(key, default)|
    assert runtime =~ ~S|required_runtime_value.|
  end

  test "P2P transport is local-only unless explicitly enabled" do
    runtime = File.read!(Path.join(@root, "config/runtime.exs"))

    [p2p_block] =
      Regex.run(~r/p2p_enabled =\n(?<block>.*?\n\n)p2p_listen_ip/s, runtime, capture: ["block"])

    assert p2p_block =~ ~S|env_or_dotenv.("TECHTREE_P2P_ENABLED", "false")|
    refute p2p_block =~ ~S|else: "true"|
  end
end
