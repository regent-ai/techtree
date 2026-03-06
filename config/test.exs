import Config

dotenv_values =
  Path.expand("../.env", __DIR__)
  |> File.read()
  |> case do
    {:ok, contents} ->
      contents
      |> String.split("\n")
      |> Enum.reduce(%{}, fn line, acc ->
        trimmed = String.trim(line)

        cond do
          trimmed == "" or String.starts_with?(trimmed, "#") ->
            acc

          true ->
            case String.split(trimmed, "=", parts: 2) do
              [key, value] ->
                normalized =
                  value
                  |> String.trim()
                  |> String.trim_leading("\"")
                  |> String.trim_trailing("\"")
                  |> String.trim_leading("'")
                  |> String.trim_trailing("'")

                Map.put(acc, String.trim(key), normalized)

              _ ->
                acc
            end
        end
      end)

    _ ->
      %{}
  end

env_or_dotenv = fn key, default ->
  System.get_env(key) || Map.get(dotenv_values, key, default)
end

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
local_database_url = env_or_dotenv.("LOCAL_DATABASE_URL", "")
partition = System.get_env("MIX_TEST_PARTITION")

if is_binary(local_database_url) and String.trim(local_database_url) != "" do
  parsed = URI.parse(local_database_url)
  base_path = parsed.path || "/tech_tree_test"
  partition_suffix = if is_binary(partition), do: partition, else: ""
  partitioned_path = "#{base_path}#{partition_suffix}"
  test_url = %{parsed | path: partitioned_path} |> URI.to_string()

  config :tech_tree, TechTree.Repo,
    url: test_url,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
else
  db_user =
    env_or_dotenv.("DB_USER", env_or_dotenv.("PGUSER", System.get_env("USER") || "postgres"))

  db_pass = env_or_dotenv.("DB_PASS", env_or_dotenv.("PGPASSWORD", ""))
  db_host = env_or_dotenv.("DB_HOST", env_or_dotenv.("PGHOST", "localhost"))
  db_port = env_or_dotenv.("DB_PORT", env_or_dotenv.("PGPORT", "5432"))
  db_name = "tech_tree_test#{partition}"

  config :tech_tree, TechTree.Repo,
    username: db_user,
    password: db_pass,
    hostname: db_host,
    port: String.to_integer(db_port),
    database: db_name,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
end

config :tech_tree, Oban, testing: :manual
# Keep SIWA verification bypass limited to tests to satisfy startup runtime guard.
config :tech_tree, :siwa, skip_http_verify: true
config :tech_tree, :base, mode: :stub, chain_id: 8453
config :tech_tree, TechTree.IPFS.LighthouseClient, mock_uploads: true

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tech_tree, TechTreeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "tavuddhIfvrfWYPO4fSuwyVF2U+JXIEXMzSImbXrA4qPQZhgZWn3en//evrlzC+z",
  server: false

# In test we don't send emails
config :tech_tree, TechTree.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
