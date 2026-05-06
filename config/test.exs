import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
partition = System.get_env("MIX_TEST_PARTITION")
db_name = "tech_tree_test#{partition}"
database_url = System.get_env("LOCAL_DATABASE_URL") || System.get_env("DATABASE_URL") || ""

if String.trim(database_url) != "" do
  parsed = URI.parse(database_url)
  test_path = "/#{db_name}"

  config :tech_tree, TechTree.Repo,
    url: URI.to_string(%{parsed | path: test_path}),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
else
  db_user =
    System.get_env("DB_USER") || System.get_env("PGUSER") || System.get_env("USER") || "postgres"

  db_pass = System.get_env("DB_PASS") || System.get_env("PGPASSWORD") || ""
  db_host = System.get_env("DB_HOST") || System.get_env("PGHOST") || "localhost"
  db_port = System.get_env("DB_PORT") || System.get_env("PGPORT") || "5432"

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
config :tech_tree, TechTreeWeb.Telemetry, enable_periodic_poller: false
config :tech_tree, TechTree.Observability, drop_metrics_groups: [:oban_queue_poll_metrics]
config :tech_tree, TechTree.RateLimit, backend: :cachex

config :tech_tree, TechTree.P2P,
  enabled: false,
  identity_path: Path.expand("../tmp/p2p-identity-test.json", __DIR__)

config :tech_tree, :siwa, internal_url: "http://127.0.0.1:0"

config :tech_tree, :ethereum, mode: :stub, chain_id: 8_453
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
