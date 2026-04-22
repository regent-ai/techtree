defmodule TechTreeWeb.LandingLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.PublicSite
  alias TechTreeWeb.LandingComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "TechTree")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:install_command, PublicSite.install_command())
     |> assign(:signal_items, PublicSite.landing_signal_items())}
  end

  @impl true
  def render(assigns), do: LandingComponents.landing_page(assigns)
end
