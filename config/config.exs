# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :tech_tree,
  runtime_env: config_env(),
  ecto_repos: [TechTree.Repo],
  generators: [timestamp_type: :utc_datetime]

config :tech_tree, Oban,
  repo: TechTree.Repo,
  queues: [
    canonical: 10,
    chain: 10,
    index: 20,
    realtime: 25,
    xmtp: 10,
    maintenance: 5
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 14},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/2 * * * *", TechTree.Workers.ReconcileBaseNodesWorker},
       {"*/5 * * * *", TechTree.Workers.VerifyPinnedArtifactsWorker},
       {"*/10 * * * *", TechTree.Workers.RebuildHotScoresWorker}
     ]}
  ]

config :tech_tree, :dragonfly_host, System.get_env("DRAGONFLY_HOST", "localhost")
config :tech_tree, :dragonfly_port, String.to_integer(System.get_env("DRAGONFLY_PORT", "6379"))

config :tech_tree, :system_agent_id, System.get_env("SYSTEM_AGENT_ID", "1")
config :tech_tree, :internal_shared_secret, System.get_env("INTERNAL_SHARED_SECRET", "")

config :tech_tree, :privy,
  app_id: System.get_env("PRIVY_APP_ID", ""),
  verification_key: System.get_env("PRIVY_VERIFICATION_KEY", "")

config :tech_tree, :siwa,
  internal_url: System.get_env("SIWA_INTERNAL_URL", "http://siwa-sidecar:4100"),
  shared_secret: System.get_env("SIWA_SHARED_SECRET", "")

base_chain_id = System.get_env("TECHTREE_CHAIN_ID") || System.get_env("BASE_CHAIN_ID")

config :tech_tree, :base,
  mode: System.get_env("TECHTREE_BASE_MODE", "auto"),
  rpc_url:
    System.get_env("BASE_RPC_URL") || System.get_env("BASE_SEPOLIA_RPC_URL") ||
      System.get_env("ANVIL_RPC_URL"),
  registry_address: System.get_env("REGISTRY_CONTRACT_ADDRESS") || System.get_env("TECHTREE_REGISTRY"),
  writer_private_key:
    System.get_env("REGISTRY_WRITER_PRIVATE_KEY") || System.get_env("BASE_SEPOLIA_PRIVATE_KEY") ||
      System.get_env("ANVIL_PRIVATE_KEY"),
  chain_id: base_chain_id,
  cast_bin: System.get_env("CAST_BIN", "cast")

config :tech_tree, TechTree.IPFS.LighthouseClient,
  api_key: System.get_env("LIGHTHOUSE_API_KEY", ""),
  base_url: System.get_env("LIGHTHOUSE_BASE_URL", "https://upload.lighthouse.storage"),
  gateway_base: System.get_env("LIGHTHOUSE_GATEWAY_BASE", "https://gateway.lighthouse.storage/ipfs"),
  storage_type: System.get_env("LIGHTHOUSE_STORAGE_TYPE", "annual")

# Configure the endpoint
config :tech_tree, TechTreeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TechTreeWeb.ErrorHTML, json: TechTreeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TechTree.PubSub,
  live_view: [signing_salt: "t8EdfKC9"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :tech_tree, TechTree.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  tech_tree: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  tech_tree: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
