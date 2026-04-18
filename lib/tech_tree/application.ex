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
    dragonfly_children = if dragonfly_enabled?(), do: [dragonfly_child_spec()], else: []

    children =
      [
        TechTreeWeb.Telemetry,
        TechTree.Repo,
        {DNSCluster, query: Application.get_env(:tech_tree, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: TechTree.PubSub},
        TechTree.XmtpIdentity,
        TechTree.P2P.Supervisor,
        {Oban, Application.fetch_env!(:tech_tree, Oban)},
        TechTreeWeb.Endpoint
      ] ++ dragonfly_children

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TechTree.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc false
  @spec validate_siwa_runtime_config!(atom(), keyword() | term()) :: :ok
  def validate_siwa_runtime_config!(runtime_env, siwa_cfg) when is_list(siwa_cfg) do
    skip_http_verify? = Keyword.get(siwa_cfg, :skip_http_verify, false) == true
    internal_url = Keyword.get(siwa_cfg, :internal_url)
    shared_secret = Keyword.get(siwa_cfg, :shared_secret)

    if skip_http_verify? and runtime_env != :test do
      raise """
      invalid SIWA configuration: :siwa, skip_http_verify may only be enabled in :test.
      """
    end

    if runtime_env == :prod do
      unless is_binary(internal_url) and String.trim(internal_url) != "" do
        raise """
        invalid SIWA configuration: :siwa, internal_url must be configured in :prod.
        """
      end

      unless is_binary(shared_secret) and String.trim(shared_secret) != "" do
        raise """
        invalid SIWA configuration: :siwa, shared_secret must be configured in :prod.
        """
      end
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

  @spec dragonfly_enabled?() :: boolean()
  defp dragonfly_enabled? do
    Application.get_env(:tech_tree, :dragonfly_enabled, true) == true
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
