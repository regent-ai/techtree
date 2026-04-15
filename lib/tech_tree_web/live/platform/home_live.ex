defmodule TechTreeWeb.Platform.HomeLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.PlatformComponents

  alias TechTree.Platform

  @impl true
  def mount(_params, _session, socket) do
    snapshot = Platform.dashboard_snapshot()

    {:ok,
     socket
     |> assign(:page_title, "Platform")
     |> assign(:route_key, "home")
     |> assign(:snapshot, snapshot)
     |> assign(:client_config, platform_client_config())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.platform_shell
        route_key={@route_key}
        title="Regent Platform"
        kicker="Platform"
        subtitle="Start here to review imported records, open platform tools, and check service status."
        client_config={@client_config}
      >
        <section
          id="platform-home-scene"
          phx-hook="PlatformScene"
          data-scene="home"
          class="grid gap-4 xl:grid-cols-[1.1fr_0.9fr]"
        >
          <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-2">
            <.stat_card
              label="Agents"
              value={Integer.to_string(@snapshot.counts.agents)}
              copy="Imported hosted and indexed agent records."
              tone="signal"
            />
            <.stat_card
              label="Tiles"
              value={Integer.to_string(@snapshot.counts.tiles)}
              copy="Frontier tiles ready to browse."
              tone="ocean"
            />
            <.stat_card
              label="Names"
              value={Integer.to_string(@snapshot.counts.names)}
              copy="Name claims ready to review."
            />
          </div>

          <.surface_card
            eyebrow="Front door"
            title="One shell, many surfaces"
            copy="Jump between platform areas from one clear starting point."
          >
            <div class="grid gap-3 sm:grid-cols-2">
              <%= for item <- nav_items() |> Enum.reject(&(&1.key == "home")) |> Enum.take(6) do %>
                <.link
                  navigate={item.href}
                  class="group rounded-[1.4rem] border border-black/8 bg-white/68 px-4 py-4 transition hover:-translate-y-0.5 hover:border-black/14 hover:bg-white dark:border-white/10 dark:bg-white/5 dark:hover:border-white/18 dark:hover:bg-white/10"
                >
                  <p class="font-display text-[0.72rem] uppercase tracking-[0.22em] text-amber-600 dark:text-amber-300">
                    {item.label}
                  </p>
                  <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">{item.copy}</p>
                </.link>
              <% end %>
            </div>
          </.surface_card>
        </section>

        <section class="grid gap-4 xl:grid-cols-[0.95fr_1.05fr]">
          <.surface_card
            eyebrow="Recent agents"
            title="Imported creation records"
            copy="Review the latest imported agents and open any record for details."
          >
            <%= if @snapshot.recent_agents == [] do %>
              <.empty_state message="No agents have been imported yet." />
            <% else %>
              <div class="grid gap-3">
                <%= for agent <- @snapshot.recent_agents do %>
                  <.link
                    navigate={"/platform/agents/#{agent.slug}"}
                    class="rounded-[1.4rem] border border-black/8 bg-white/68 px-4 py-4 transition hover:border-black/14 hover:bg-white dark:border-white/10 dark:bg-white/5 dark:hover:border-white/18 dark:hover:bg-white/10"
                  >
                    <div class="flex items-start justify-between gap-3">
                      <div>
                        <p class="font-display text-lg">{agent.display_name}</p>
                        <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                          {agent.summary || "No summary imported yet."}
                        </p>
                      </div>
                      <.status_badge status={agent.status} />
                    </div>
                  </.link>
                <% end %>
              </div>
            <% end %>
          </.surface_card>

          <.surface_card
            eyebrow="Ops"
            title="Facilitator and live infrastructure"
            copy="Check service status and the current public chat path from one place."
          >
            <div class="grid gap-3 sm:grid-cols-2">
              <div class="rounded-[1.4rem] border border-black/8 bg-white/68 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                <p class="text-[0.68rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                  Facilitator status
                </p>
                <div class="mt-3">
                  <.status_badge status={Atom.to_string(@snapshot.facilitator.status)} />
                </div>
                <p class="mt-3 text-sm leading-6 text-slate-600 dark:text-slate-300">
                  {@snapshot.facilitator.base_url ||
                    "No Facilitator URL is configured for this environment."}
                </p>
              </div>
              <div class="rounded-[1.4rem] border border-black/8 bg-white/68 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                <p class="text-[0.68rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                  Chatbox relay
                </p>
                <p class="mt-3 text-2xl leading-none">public</p>
                <p class="mt-3 text-sm leading-6 text-slate-600 dark:text-slate-300">
                  Public chat is available through the main room and relay path.
                </p>
              </div>
            </div>
          </.surface_card>
        </section>
      </.platform_shell>
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
