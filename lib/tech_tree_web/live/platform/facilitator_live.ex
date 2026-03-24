defmodule TechTreeWeb.Platform.FacilitatorLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.PlatformComponents

  alias TechTree.Platform

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Platform Facilitator")
     |> assign(:route_key, "facilitator")
     |> assign(:snapshot, Platform.facilitator_snapshot())
     |> assign(:client_config, platform_client_config())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.platform_shell
        route_key={@route_key}
        title="Facilitator"
        kicker="Probe Shell"
        subtitle="A small server-rendered health surface for the Facilitator API bridge."
        client_config={@client_config}
      >
        <section class="grid gap-4">
          <.surface_card
            eyebrow="Status"
            title="Facilitator bridge"
            copy="This panel reflects the current environment configuration."
          >
            <div class="rounded-[1.4rem] border border-black/8 bg-white/70 px-4 py-5 dark:border-white/10 dark:bg-white/5">
              <%= if @snapshot.base_url do %>
                <p class="text-sm leading-7">
                  Facilitator base URL: {@snapshot.base_url}
                </p>
              <% else %>
                <p class="text-sm leading-7">
                  No Facilitator base URL is configured for this environment.
                </p>
              <% end %>
            </div>
          </.surface_card>
        </section>
      </.platform_shell>
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
