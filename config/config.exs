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
    maintenance: 5
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 14},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/10 * * * *", TechTree.Workers.RebuildHotScoresWorker}
     ]}
  ]

config :tech_tree, :system_agent_id, System.get_env("SYSTEM_AGENT_ID", "1")

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

config :tech_tree, TechTree.Observability,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  grafana: :disabled,
  metrics_server: :disabled

config :tech_tree, TechTree.P2P,
  enabled: false,
  listen_ip: {127, 0, 0, 1},
  listen_port: 40_001,
  bootstrap_peers: [],
  min_ready_peers: 1,
  identity_path: nil,
  origin_node_id: "techtree-dev-01",
  topic_prefix: "regent.dev.chatbox",
  allowed_peer_ids: [],
  redial_interval_ms: 5_000,
  health_interval_ms: 2_000,
  max_message_bytes: 32_768

config :tech_tree, TechTree.Xmtp,
  rooms: [
    %{
      key: "techtree_main_chat",
      name: "TechTree Main Chat",
      description: "The shared TechTree chat room.",
      app_data: "techtree-main-chat",
      agent_private_key: nil,
      moderator_wallets: [],
      capacity: 200,
      presence_timeout_ms: :timer.minutes(2),
      presence_check_interval_ms: :timer.seconds(30),
      policy_options: %{
        allowed_kinds: [:human, :agent],
        required_claims: %{}
      }
    },
    %{
      key: "techtree_agents",
      name: "TechTree Agents",
      description: "A room reserved for agent identities.",
      app_data: "techtree-agents",
      agent_private_key: nil,
      moderator_wallets: [],
      capacity: 200,
      presence_timeout_ms: :timer.minutes(2),
      presence_check_interval_ms: :timer.seconds(30),
      policy_options: %{
        allowed_kinds: [:agent],
        required_claims: %{}
      }
    }
  ]

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
      ~w(js/app.ts js/home.ts js/platform-auth-entry.ts --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=. --alias:wgsl_reflect=./js/shims/wgsl-reflect.ts),
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
