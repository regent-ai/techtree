defmodule TechTreeWeb.Platform.CreatorLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.PlatformComponents

  alias TechTree.Platform

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Platform Creator")
     |> assign(:route_key, "creator")
     |> assign(:agents, Platform.list_agents(limit: 16))
     |> assign(:selected_agent, nil)
     |> assign(:client_config, platform_client_config())}
  end

  @impl true
  def handle_event("select-agent", %{"slug" => slug}, socket) do
    {:noreply, assign(socket, :selected_agent, Platform.get_agent_by_slug(slug))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.platform_shell
        route_key={@route_key}
        title="Creator"
        kicker="Launch Packets"
        subtitle="Review launch candidates and inspect the details for one agent at a time."
        client_config={@client_config}
      >
        <section id="platform-creator-hook" class="grid gap-4 xl:grid-cols-[1.05fr_0.95fr]">
          <.surface_card
            eyebrow="Agents"
            title="Choose a launch candidate"
            copy="Pick an agent from the list to load its details."
          >
            <div class="grid gap-3 sm:grid-cols-2">
              <%= for agent <- @agents do %>
                <button
                  type="button"
                  phx-click="select-agent"
                  phx-value-slug={agent.slug}
                  class="rounded-[1.4rem] border border-black/8 bg-white/70 px-4 py-4 text-left transition hover:border-black/14 hover:bg-white dark:border-white/10 dark:bg-white/5 dark:hover:border-white/18 dark:hover:bg-white/10"
                >
                  <p class="font-display text-lg">{agent.display_name}</p>
                  <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                    {agent.slug}
                  </p>
                </button>
              <% end %>
            </div>
          </.surface_card>

          <.surface_card
            eyebrow="Packet"
            title="Selected agent"
            copy="Review the selected agent before you move on."
          >
            <%= if @selected_agent do %>
              <div class="grid gap-3">
                <div class="rounded-[1.4rem] border border-black/8 bg-black/5 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                  <p class="font-display text-2xl">{@selected_agent.display_name}</p>
                  <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                    {@selected_agent.summary || "No summary imported yet."}
                  </p>
                </div>

                <dl class="grid gap-3">
                  <div class="rounded-[1.4rem] border border-black/8 bg-white/70 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                    <dt class="text-[0.68rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                      Owner address
                    </dt>
                    <dd class="mt-2 break-all text-sm leading-6">
                      {@selected_agent.owner_address || "n/a"}
                    </dd>
                  </div>
                  <div class="rounded-[1.4rem] border border-black/8 bg-white/70 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                    <dt class="text-[0.68rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                      Status
                    </dt>
                    <dd class="mt-2 text-sm leading-6">{@selected_agent.status}</dd>
                  </div>
                </dl>
              </div>
            <% else %>
              <.empty_state message="Select an imported agent to inspect its launch packet." />
            <% end %>
          </.surface_card>
        </section>
      </.platform_shell>
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
