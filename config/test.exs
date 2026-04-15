import Config

Code.require_file("env_local.exs", __DIR__)

env_or_dotenv = fn key, default ->
  TechTree.ConfigEnvLocal.fetch(key, default)
end

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
partition = System.get_env("MIX_TEST_PARTITION")

db_user =
  System.get_env("DB_USER") || System.get_env("PGUSER") || System.get_env("USER") || "postgres"

db_pass = System.get_env("DB_PASS") || System.get_env("PGPASSWORD") || ""
db_host = System.get_env("DB_HOST") || System.get_env("PGHOST") || "localhost"
db_port = System.get_env("DB_PORT") || System.get_env("PGPORT") || "5432"
db_name = "tech_tree_test#{partition}"

config :tech_tree, TechTree.Repo,
  username: db_user,
  password: db_pass,
  hostname: db_host,
  port: String.to_integer(db_port),
  database: db_name,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :tech_tree, Oban, testing: :manual
config :tech_tree, TechTreeWeb.Telemetry, enable_periodic_poller: false
config :tech_tree, TechTree.RateLimit, backend: :local

config :tech_tree, TechTree.P2P,
  enabled: false,
  identity_path: Path.expand("../tmp/p2p-identity-test.json", __DIR__)

# Keep SIWA verification bypass limited to tests to satisfy startup runtime guard.
config :tech_tree, :siwa, skip_http_verify: true
config :tech_tree, :ethereum, mode: :stub, chain_id: 11_155_111
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
