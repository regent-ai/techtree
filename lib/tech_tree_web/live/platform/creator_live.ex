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
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :selected_agent, selected_agent(params))}
  end

  @impl true
  def handle_event("select-agent", %{"slug" => slug}, socket) do
    {:noreply, push_patch(socket, to: creator_path(slug))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.platform_shell
        route_key={@route_key}
        title="Creator"
        kicker="Launch Packets"
        subtitle="Review one launch candidate at a time, then jump into the route that helps you act on what you found."
        client_config={@client_config}
      >
        <section id="platform-creator-hook" class="grid gap-4 xl:grid-cols-[1.05fr_0.95fr]">
          <.surface_card
            eyebrow="Agents"
            title="Choose a launch candidate"
            copy="Pick an agent from the list. The selected record stays in the URL so you can reload or share this view."
          >
            <div class="grid gap-3 sm:grid-cols-2">
              <%= for agent <- @agents do %>
                <button
                  type="button"
                  phx-click="select-agent"
                  phx-value-slug={agent.slug}
                  class={[
                    "rounded-[1.4rem] border px-4 py-4 text-left transition hover:border-black/14 hover:bg-white dark:border-white/10 dark:hover:border-white/18 dark:hover:bg-white/10",
                    if(@selected_agent && @selected_agent.slug == agent.slug,
                      do:
                        "border-amber-300/70 bg-amber-50/90 shadow-[0_16px_44px_-32px_rgba(217,119,6,0.45)] dark:bg-amber-200/10 dark:border-amber-300/40",
                      else: "border-black/8 bg-white/70 dark:bg-white/5"
                    )
                  ]}
                >
                  <p class="font-display text-lg">{agent.display_name}</p>
                  <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                    {agent.slug}
                  </p>
                  <p
                    :if={@selected_agent && @selected_agent.slug == agent.slug}
                    class="mt-3 text-[0.66rem] uppercase tracking-[0.18em] text-amber-700 dark:text-amber-300"
                  >
                    Selected
                  </p>
                </button>
              <% end %>
            </div>
          </.surface_card>

          <.surface_card
            eyebrow="Packet"
            title="Selected agent"
            copy="Inspect the selected record, then move into the route that matches the next step."
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

                <div class="flex flex-wrap gap-2">
                  <.link
                    navigate={"/platform/agents/#{@selected_agent.slug}"}
                    class="btn fp-command-secondary"
                  >
                    Open full agent record
                  </.link>
                  <.link navigate="/platform/agents" class="btn fp-command-secondary">
                    Browse the full catalog
                  </.link>
                </div>
              </div>
            <% else %>
              <.empty_state message="Select an imported agent to inspect its launch packet, then open the full record if you need more detail." />
            <% end %>
          </.surface_card>
        </section>
      </.platform_shell>
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  defp selected_agent(%{"agent" => slug}) when is_binary(slug) and slug != "",
    do: Platform.get_agent_by_slug(slug)

  defp selected_agent(_params), do: nil

  defp creator_path(slug) when is_binary(slug) and slug != "" do
    ~p"/platform/creator?#{%{"agent" => slug}}"
  end
end
