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

required_runtime_value = fn key, value, hint ->
  normalized =
    cond do
      is_binary(value) -> String.trim(value)
      is_nil(value) -> ""
      true -> to_string(value) |> String.trim()
    end

  if config_env() == :prod and normalized == "" do
    raise """
    environment variable #{key} is missing.
    #{hint}
    """
  end

  value
end

validate_chain_id = fn chain_id ->
  supported_chain_ids = ["31337", "84532", "8453", "11155111", "1"]

  normalized =
    cond do
      is_binary(chain_id) -> String.trim(chain_id)
      is_integer(chain_id) -> Integer.to_string(chain_id)
      true -> ""
    end

  if normalized in supported_chain_ids do
    normalized
  else
    raise """
    environment variable TECHTREE_CHAIN_ID is invalid: #{inspect(chain_id)}.
    Supported values: #{Enum.join(supported_chain_ids, ", ")}
    """
  end
end

cfg_fetch = fn cfg, key ->
  cond do
    Keyword.keyword?(cfg) -> Keyword.get(cfg, key)
    is_map(cfg) -> Map.get(cfg, key, Map.get(cfg, Atom.to_string(key)))
    true -> nil
  end
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/tech_tree start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :tech_tree, TechTreeWeb.Endpoint, server: true
end

config :tech_tree, TechTreeWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

promex_metrics_enabled =
  env_or_dotenv.("PROMEX_METRICS_ENABLED", if(config_env() == :test, do: "false", else: "true"))
  |> String.downcase()
  |> then(&(&1 in ["1", "true", "yes", "on"]))

if promex_metrics_enabled do
  config :tech_tree, TechTree.Observability,
    metrics_server: [
      port: env_or_dotenv.("PROMEX_METRICS_PORT", "9568"),
      path: env_or_dotenv.("PROMEX_METRICS_PATH", "/metrics"),
      protocol: :http,
      pool_size: String.to_integer(env_or_dotenv.("PROMEX_METRICS_POOL_SIZE", "5")),
      auth_strategy: :none
    ]
else
  config :tech_tree, TechTree.Observability, metrics_server: :disabled
end

dragonfly_enabled_env = env_or_dotenv.("DRAGONFLY_ENABLED", "true") |> String.downcase()

config :tech_tree, :dragonfly_host, env_or_dotenv.("DRAGONFLY_HOST", "localhost")
config :tech_tree, :dragonfly_port, String.to_integer(env_or_dotenv.("DRAGONFLY_PORT", "6379"))
config :tech_tree, :dragonfly_enabled, dragonfly_enabled_env in ["1", "true", "yes", "on"]

config :tech_tree, :privy,
  app_id: env_or_dotenv.("PRIVY_APP_ID", ""),
  verification_key: env_or_dotenv.("PRIVY_VERIFICATION_KEY", "")

config :tech_tree, :internal_shared_secret, env_or_dotenv.("INTERNAL_SHARED_SECRET", "")

config :tech_tree, :siwa,
  internal_url: env_or_dotenv.("SIWA_INTERNAL_URL", "http://siwa-sidecar:4100"),
  shared_secret: env_or_dotenv.("SIWA_SHARED_SECRET", ""),
  http_connect_timeout_ms:
    String.to_integer(env_or_dotenv.("SIWA_HTTP_CONNECT_TIMEOUT_MS", "2000")),
  http_receive_timeout_ms:
    String.to_integer(env_or_dotenv.("SIWA_HTTP_RECEIVE_TIMEOUT_MS", "5000"))

existing_ethereum_cfg = Application.get_env(:tech_tree, :ethereum, [])

ethereum_chain_id =
  env_or_dotenv.(
    "TECHTREE_CHAIN_ID",
    env_or_dotenv.("ETHEREUM_CHAIN_ID", cfg_fetch.(existing_ethereum_cfg, :chain_id))
  )
  |> validate_chain_id.()

ethereum_rpc_url =
  case ethereum_chain_id do
    "84532" ->
      env_or_dotenv.("BASE_SEPOLIA_RPC_URL", env_or_dotenv.("ANVIL_RPC_URL", nil))

    "11155111" ->
      env_or_dotenv.("ETHEREUM_SEPOLIA_RPC_URL", env_or_dotenv.("ANVIL_RPC_URL", nil))

    "31337" ->
      env_or_dotenv.("ANVIL_RPC_URL", nil)

    _ ->
      env_or_dotenv.("ETHEREUM_MAINNET_RPC_URL", env_or_dotenv.("ETHEREUM_RPC_URL", nil))
  end

ethereum_writer_private_key =
  case ethereum_chain_id do
    "84532" ->
      env_or_dotenv.("BASE_SEPOLIA_PRIVATE_KEY", env_or_dotenv.("ANVIL_PRIVATE_KEY", nil))

    "11155111" ->
      env_or_dotenv.("ETHEREUM_SEPOLIA_PRIVATE_KEY", env_or_dotenv.("ANVIL_PRIVATE_KEY", nil))

    "31337" ->
      env_or_dotenv.("ANVIL_PRIVATE_KEY", nil)

    _ ->
      env_or_dotenv.(
        "ETHEREUM_MAINNET_PRIVATE_KEY",
        env_or_dotenv.("ETHEREUM_PRIVATE_KEY", nil)
      )
  end

config :tech_tree, :ethereum,
  mode:
    env_or_dotenv.(
      "TECHTREE_ETHEREUM_MODE",
      cfg_fetch.(existing_ethereum_cfg, :mode) || "auto"
    ),
  rpc_url: ethereum_rpc_url || cfg_fetch.(existing_ethereum_cfg, :rpc_url),
  registry_address:
    env_or_dotenv.(
      "REGISTRY_CONTRACT_ADDRESS",
      env_or_dotenv.(
        "TECHTREE_REGISTRY",
        cfg_fetch.(existing_ethereum_cfg, :registry_address)
      )
    ),
  writer_private_key:
    env_or_dotenv.(
      "REGISTRY_WRITER_PRIVATE_KEY",
      ethereum_writer_private_key || cfg_fetch.(existing_ethereum_cfg, :writer_private_key)
    ),
  chain_id: ethereum_chain_id,
  cast_bin: env_or_dotenv.("CAST_BIN", cfg_fetch.(existing_ethereum_cfg, :cast_bin) || "cast")

registry_address =
  env_or_dotenv.(
    "REGISTRY_CONTRACT_ADDRESS",
    env_or_dotenv.(
      "TECHTREE_REGISTRY",
      cfg_fetch.(existing_ethereum_cfg, :registry_address)
    )
  )

registry_writer_private_key =
  env_or_dotenv.(
    "REGISTRY_WRITER_PRIVATE_KEY",
    ethereum_writer_private_key || cfg_fetch.(existing_ethereum_cfg, :writer_private_key)
  )

lighthouse_api_key = env_or_dotenv.("LIGHTHOUSE_API_KEY", "")

config :tech_tree, TechTree.IPFS.LighthouseClient,
  api_key: lighthouse_api_key,
  base_url: env_or_dotenv.("LIGHTHOUSE_BASE_URL", "https://upload.lighthouse.storage"),
  gateway_base:
    env_or_dotenv.("LIGHTHOUSE_GATEWAY_BASE", "https://gateway.lighthouse.storage/ipfs"),
  storage_type: env_or_dotenv.("LIGHTHOUSE_STORAGE_TYPE", "annual"),
  mock_uploads: false

config :tech_tree, :autoskill,
  chains: %{
    84_532 => %{
      settlement_contract_address:
        env_or_dotenv.("AUTOSKILL_BASE_SEPOLIA_SETTLEMENT_CONTRACT", ""),
      usdc_token_address: env_or_dotenv.("AUTOSKILL_BASE_SEPOLIA_USDC_TOKEN", ""),
      treasury_address: env_or_dotenv.("AUTOSKILL_BASE_SEPOLIA_TREASURY_ADDRESS", "")
    },
    8_453 => %{
      settlement_contract_address:
        env_or_dotenv.("AUTOSKILL_BASE_MAINNET_SETTLEMENT_CONTRACT", ""),
      usdc_token_address: env_or_dotenv.("AUTOSKILL_BASE_MAINNET_USDC_TOKEN", ""),
      treasury_address: env_or_dotenv.("AUTOSKILL_BASE_MAINNET_TREASURY_ADDRESS", "")
    }
  }

p2p_enabled =
  env_or_dotenv.("TECHTREE_P2P_ENABLED", if(config_env() == :test, do: "false", else: "true"))
  |> String.downcase()
  |> then(&(&1 in ["1", "true", "yes", "on"]))

p2p_listen_ip =
  env_or_dotenv.("TECHTREE_P2P_LISTEN_IP", "0.0.0.0")
  |> String.split(".")
  |> Enum.map(&String.to_integer/1)
  |> List.to_tuple()

p2p_identity_path_default =
  Path.expand("../tmp/p2p-identity-#{config_env()}.json", __DIR__)

config :tech_tree, TechTree.P2P,
  enabled: p2p_enabled,
  listen_ip: p2p_listen_ip,
  listen_port: String.to_integer(env_or_dotenv.("TECHTREE_P2P_LISTEN_PORT", "40001")),
  bootstrap_peers:
    env_or_dotenv.("TECHTREE_P2P_BOOTSTRAP_PEERS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1),
  min_ready_peers: String.to_integer(env_or_dotenv.("TECHTREE_P2P_MIN_READY_PEERS", "1")),
  identity_path: env_or_dotenv.("TECHTREE_P2P_IDENTITY_PATH", p2p_identity_path_default),
  origin_node_id: env_or_dotenv.("TECHTREE_P2P_ORIGIN_NODE_ID", "techtree-#{config_env()}"),
  topic_prefix: env_or_dotenv.("TECHTREE_P2P_TOPIC_PREFIX", "regent.#{config_env()}.trollbox"),
  allowed_peer_ids:
    env_or_dotenv.("TECHTREE_P2P_ALLOWED_PEER_IDS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1),
  redial_interval_ms:
    String.to_integer(env_or_dotenv.("TECHTREE_P2P_REDIAL_INTERVAL_MS", "5000")),
  health_interval_ms:
    String.to_integer(env_or_dotenv.("TECHTREE_P2P_HEALTH_INTERVAL_MS", "2000")),
  max_message_bytes: String.to_integer(env_or_dotenv.("TECHTREE_P2P_MAX_MESSAGE_BYTES", "32768"))

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :tech_tree, TechTree.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  required_runtime_value.(
    "INTERNAL_SHARED_SECRET",
    env_or_dotenv.("INTERNAL_SHARED_SECRET", ""),
    "Set INTERNAL_SHARED_SECRET before enabling internal-only routes."
  )

  required_runtime_value.(
    "SIWA_SHARED_SECRET",
    env_or_dotenv.("SIWA_SHARED_SECRET", ""),
    "Set SIWA_SHARED_SECRET to the same value as the sidecar SIWA_HMAC_SECRET."
  )

  required_runtime_value.(
    "PRIVY_APP_ID",
    env_or_dotenv.("PRIVY_APP_ID", ""),
    "Set the production Privy app id before browser signoff or deploy."
  )

  required_runtime_value.(
    "PRIVY_VERIFICATION_KEY",
    env_or_dotenv.("PRIVY_VERIFICATION_KEY", ""),
    "Set the production Privy verification key before browser signoff or deploy."
  )

  if ethereum_chain_id == "84532" do
    required_runtime_value.(
      "BASE_SEPOLIA_RPC_URL",
      ethereum_rpc_url,
      "Base Sepolia publishing needs a reachable RPC URL."
    )

    required_runtime_value.(
      "REGISTRY_CONTRACT_ADDRESS",
      registry_address,
      "Set the Base Sepolia registry contract address for launch publishing."
    )

    required_runtime_value.(
      "REGISTRY_WRITER_PRIVATE_KEY",
      registry_writer_private_key,
      "Set the funded Base Sepolia registry writer key for launch publishing."
    )

    required_runtime_value.(
      "LIGHTHOUSE_API_KEY",
      lighthouse_api_key,
      "Set LIGHTHOUSE_API_KEY before any launch publish flow."
    )
  end

  config :tech_tree, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :tech_tree, TechTreeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :tech_tree, TechTreeWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :tech_tree, TechTreeWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :tech_tree, TechTree.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
