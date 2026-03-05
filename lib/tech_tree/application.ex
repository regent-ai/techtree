defmodule TechTree.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @default_dragonfly_host "localhost"
  @default_dragonfly_port 6379

  @impl true
  def start(_type, _args) do
    :ok = enforce_siwa_http_verify_runtime_guard!()

    children = [
      TechTreeWeb.Telemetry,
      TechTree.Repo,
      {DNSCluster, query: Application.get_env(:tech_tree, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TechTree.PubSub},
      dragonfly_child_spec(),
      {Oban, Application.fetch_env!(:tech_tree, Oban)},
      TechTreeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TechTree.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc false
  @spec validate_siwa_runtime_config!(atom(), keyword() | term()) :: :ok
  def validate_siwa_runtime_config!(runtime_env, siwa_cfg) when is_list(siwa_cfg) do
    skip_http_verify? = Keyword.get(siwa_cfg, :skip_http_verify, false) == true

    if skip_http_verify? and runtime_env != :test do
      raise """
      invalid SIWA configuration: :siwa, skip_http_verify may only be enabled in :test.
      """
    end

    :ok
  end

  def validate_siwa_runtime_config!(_runtime_env, siwa_cfg) do
    raise ArgumentError,
          "invalid SIWA configuration: expected :siwa to be a keyword list, got: #{inspect(siwa_cfg)}"
  end

  @spec enforce_siwa_http_verify_runtime_guard!() :: :ok
  defp enforce_siwa_http_verify_runtime_guard! do
    runtime_env = Application.get_env(:tech_tree, :runtime_env, :dev)
    siwa_cfg = Application.get_env(:tech_tree, :siwa, [])
    validate_siwa_runtime_config!(runtime_env, siwa_cfg)
  end

  @spec dragonfly_child_spec() :: Supervisor.child_spec()
  defp dragonfly_child_spec do
    {Redix, name: :dragonfly, host: dragonfly_host(), port: dragonfly_port()}
  end

  @spec dragonfly_host() :: String.t()
  defp dragonfly_host do
    Application.get_env(:tech_tree, :dragonfly_host, @default_dragonfly_host)
  end

  @spec dragonfly_port() :: non_neg_integer()
  defp dragonfly_port do
    Application.get_env(:tech_tree, :dragonfly_port, @default_dragonfly_port)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TechTreeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
