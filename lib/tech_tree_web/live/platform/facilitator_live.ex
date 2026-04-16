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
        subtitle="Check whether the Facilitator service is available here, then jump into the next route that depends on it."
        client_config={@client_config}
      >
        <section class="grid gap-4 xl:grid-cols-[0.9fr_1.1fr]">
          <.surface_card
            eyebrow="Status"
            title="Facilitator connection"
            copy="Review the current service address for this environment."
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

          <.surface_card
            eyebrow="Next step"
            title="Choose the route that comes after this check"
            copy="Use the Facilitator check to confirm the environment, then move into the page that needs it."
          >
            <div class="grid gap-3 sm:grid-cols-2">
              <.link
                navigate="/platform/explorer"
                class="rounded-[1.4rem] border border-black/8 bg-white/70 px-4 py-4 transition hover:border-black/14 hover:bg-white dark:border-white/10 dark:bg-white/5 dark:hover:border-white/18 dark:hover:bg-white/10"
              >
                <p class="font-display text-lg">Open Explorer</p>
                <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                  Return to the frontier view once the environment looks ready.
                </p>
              </.link>

              <.link
                navigate="/platform"
                class="rounded-[1.4rem] border border-black/8 bg-white/70 px-4 py-4 transition hover:border-black/14 hover:bg-white dark:border-white/10 dark:bg-white/5 dark:hover:border-white/18 dark:hover:bg-white/10"
              >
                <p class="font-display text-lg">Back to Platform</p>
                <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                  Go back to the workspace launchpad when you are done here.
                </p>
              </.link>
            </div>
          </.surface_card>
        </section>
      </.platform_shell>
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
