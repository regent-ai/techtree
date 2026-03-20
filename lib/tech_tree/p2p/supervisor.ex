defmodule TechTree.P2P.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children =
      if Application.fetch_env!(:tech_tree, TechTree.P2P)[:enabled] do
        [TechTree.P2P.Transport]
      else
        []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
