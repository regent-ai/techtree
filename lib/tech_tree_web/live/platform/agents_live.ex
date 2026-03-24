defmodule TechTreeWeb.Platform.AgentsLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.PlatformComponents

  alias TechTree.Platform

  @impl true
  def mount(_params, _session, socket) do
    filters = %{"search" => "", "status" => ""}

    {:ok,
     socket
     |> assign(:page_title, "Platform Agents")
     |> assign(:route_key, "agents")
     |> assign(:filters, filters)
     |> assign(:agents, Platform.list_agents(limit: 24))
     |> assign(:client_config, platform_client_config())}
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) do
    normalized = normalize_filters(filters)

    {:noreply,
     socket
     |> assign(:filters, normalized)
     |> assign(
       :agents,
       Platform.list_agents(limit: 24, search: normalized["search"], status: normalized["status"])
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.platform_shell
        route_key={@route_key}
        title="Agents"
        kicker="Catalog"
        subtitle="A server-rendered catalog with filters and direct links to imported agent detail pages."
        client_config={@client_config}
      >
        <section class="grid gap-4 xl:grid-cols-[0.8fr_1.2fr]">
          <.surface_card
            eyebrow="Filters"
            title="Search imported agents"
            copy="Filtering stays on the server so the page remains the source of truth."
          >
            <form id="platform-agent-filters" phx-change="filters" class="grid gap-3">
              <label class="grid gap-2">
                <span class="text-[0.68rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                  Search
                </span>
                <input
                  type="text"
                  name="filters[search]"
                  value={Map.get(@filters, "search", "")}
                  placeholder="display name, slug, or summary"
                  class="input input-bordered w-full"
                />
              </label>

              <label class="grid gap-2">
                <span class="text-[0.68rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                  Status
                </span>
                <input
                  type="text"
                  name="filters[status]"
                  value={Map.get(@filters, "status", "")}
                  placeholder="ready, active, failed"
                  class="input input-bordered w-full"
                />
              </label>
            </form>
          </.surface_card>

          <.surface_card
            eyebrow="Results"
            title="Imported agent list"
            copy="Each row links to the canonical detail view."
          >
            <%= if @agents == [] do %>
              <.empty_state message="No agents match the current filters." />
            <% else %>
              <div class="grid gap-3">
                <%= for agent <- @agents do %>
                  <.link
                    navigate={"/platform/agents/#{agent.slug}"}
                    class="rounded-[1.4rem] border border-black/8 bg-white/70 px-4 py-4 transition hover:border-black/14 hover:bg-white dark:border-white/10 dark:bg-white/5 dark:hover:border-white/18 dark:hover:bg-white/10"
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
        </section>
      </.platform_shell>
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  defp normalize_filters(filters) do
    %{
      "search" => filters |> Map.get("search", "") |> normalize_text(),
      "status" => filters |> Map.get("status", "") |> normalize_text()
    }
  end

  defp normalize_text(value) when is_binary(value), do: String.trim(value)
  defp normalize_text(_), do: ""
end
