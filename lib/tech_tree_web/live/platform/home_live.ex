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
        subtitle="Start here when you need a preview of operator tools, imported records, and account-linked actions in one workspace."
        client_config={@client_config}
      >
        <section
          id="platform-home-scene"
          phx-hook="PlatformScene"
          data-scene="home"
          class="grid gap-4 xl:grid-cols-[1.1fr_0.9fr]"
        >
          <.surface_card
            eyebrow="Start here"
            title="Pick the next operator move"
            copy="Choose the page that matches what you need to do next instead of browsing every platform surface first."
          >
            <div class="grid gap-3">
              <.link
                navigate="/platform/agents"
                class="group rounded-[1.4rem] border border-black/8 bg-white/68 px-4 py-4 transition hover:-translate-y-0.5 hover:border-black/14 hover:bg-white dark:border-white/10 dark:bg-white/5 dark:hover:border-white/18 dark:hover:bg-white/10"
              >
                <div class="flex items-start justify-between gap-3">
                  <div>
                    <p class="font-display text-[0.72rem] uppercase tracking-[0.22em] text-amber-600 dark:text-amber-300">
                      Browse agents
                    </p>
                    <p class="mt-2 text-lg leading-none">
                      Start with the catalog when you need a specific agent record.
                    </p>
                    <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                      Best when you want to search by name, open a profile, or confirm an imported status.
                    </p>
                  </div>
                  <span class="text-2xl leading-none opacity-55 transition group-hover:translate-x-1 group-hover:opacity-100">
                    →
                  </span>
                </div>
              </.link>

              <.link
                navigate="/platform/explorer"
                class="group rounded-[1.4rem] border border-black/8 bg-white/68 px-4 py-4 transition hover:-translate-y-0.5 hover:border-black/14 hover:bg-white dark:border-white/10 dark:bg-white/5 dark:hover:border-white/18 dark:hover:bg-white/10"
              >
                <div class="flex items-start justify-between gap-3">
                  <div>
                    <p class="font-display text-[0.72rem] uppercase tracking-[0.22em] text-sky-700 dark:text-sky-300">
                      Inspect frontier tiles
                    </p>
                    <p class="mt-2 text-lg leading-none">
                      Use Explorer when you need the current frontier layout and drilldown path.
                    </p>
                    <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                      Best when you want to move from a broad map into one tile at a time.
                    </p>
                  </div>
                  <span class="text-2xl leading-none opacity-55 transition group-hover:translate-x-1 group-hover:opacity-100">
                    →
                  </span>
                </div>
              </.link>

              <.link
                navigate="/platform/moderation"
                class="group rounded-[1.4rem] border border-black/8 bg-white/68 px-4 py-4 transition hover:-translate-y-0.5 hover:border-black/14 hover:bg-white dark:border-white/10 dark:bg-white/5 dark:hover:border-white/18 dark:hover:bg-white/10"
              >
                <div class="flex items-start justify-between gap-3">
                  <div>
                    <p class="font-display text-[0.72rem] uppercase tracking-[0.22em] text-rose-700 dark:text-rose-300">
                      Review moderation
                    </p>
                    <p class="mt-2 text-lg leading-none">
                      Open the moderation queue when you need the fastest route into action.
                    </p>
                    <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                      Best when you are checking public content, message authors, or recent actions.
                    </p>
                  </div>
                  <span class="text-2xl leading-none opacity-55 transition group-hover:translate-x-1 group-hover:opacity-100">
                    →
                  </span>
                </div>
              </.link>
            </div>
          </.surface_card>

          <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-2">
            <.stat_card
              label="Agents"
              value={Integer.to_string(@snapshot.counts.agents)}
              copy="Imported agent records available in this workspace."
              tone="signal"
            />
            <.stat_card
              label="Tiles"
              value={Integer.to_string(@snapshot.counts.tiles)}
              copy="Frontier tiles available when records have been imported."
              tone="ocean"
            />
            <.stat_card
              label="Names"
              value={Integer.to_string(@snapshot.counts.names)}
              copy="Name claims available when records have been imported."
            />
            <.stat_card
              label="Wallet"
              value="Ready here"
              copy="Connect in the sidebar before you use account-linked actions."
            />
          </div>
        </section>

        <section class="grid gap-4 xl:grid-cols-[0.95fr_1.05fr]">
          <.surface_card
            eyebrow="Recent agents"
            title="Imported creation records"
            copy="Review the latest imported agents and open any record for details."
          >
            <%= if @snapshot.recent_agents == [] do %>
              <.empty_state message="No agents have been imported yet. Start in the catalog once the next import lands." />
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
            title="Workspace checks"
            copy="Use this area to check what is available in this workspace, then jump into the route that matches the next job."
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
                  Public chat can be reviewed from the main room when messages are present.
                </p>
              </div>
            </div>

            <div class="mt-4 flex flex-wrap gap-2">
              <.link navigate="/platform/facilitator" class="btn fp-command-secondary">
                Open Facilitator
              </.link>
              <.link navigate="/" class="btn fp-command-secondary">
                Return to public home
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
