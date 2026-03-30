defmodule TechTreeWeb.Platform.AgentLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.PlatformComponents

  alias TechTree.Platform

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    agent = Platform.get_agent_by_slug(id)

    {:ok,
     socket
     |> assign(:page_title, "Platform Agent")
     |> assign(:route_key, "agents")
     |> assign(:agent, agent)
     |> assign(:client_config, platform_client_config())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.platform_shell
        route_key={@route_key}
        title={if(@agent, do: @agent.display_name, else: "Agent not found")}
        kicker="Profile"
        subtitle={
          if(@agent,
            do: @agent.summary || "Imported profile metadata and operational references live here.",
            else: "The requested imported agent record does not exist."
          )
        }
        client_config={@client_config}
      >
        <%= if @agent do %>
          <section class="grid gap-4 xl:grid-cols-[0.9fr_1.1fr]">
            <.surface_card
              eyebrow="Identity"
              title="Imported runtime envelope"
              copy="This page replaces the old React profile route with a single LiveView source of truth."
            >
              <div class="grid gap-3">
                <div class="flex items-center justify-between gap-3">
                  <p class="font-display text-2xl">{@agent.display_name}</p>
                  <.status_badge status={@agent.status} />
                </div>
                <dl class="grid gap-3 sm:grid-cols-2">
                  <%= for {label, value} <- [
                    {"Source", @agent.source},
                    {"Owner", @agent.owner_address || "n/a"},
                    {"Agent URI", @agent.agent_uri || "n/a"},
                    {"External URL", @agent.external_url || "n/a"}
                  ] do %>
                    <div class="rounded-[1.3rem] border border-black/8 bg-white/68 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                      <dt class="text-[0.66rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                        {label}
                      </dt>
                      <dd class="mt-2 break-all text-sm leading-6">{value}</dd>
                    </div>
                  <% end %>
                </dl>
              </div>
            </.surface_card>

            <.surface_card
              eyebrow="Metadata"
              title="Protocol bindings"
              copy="Phoenix now owns the read model. Any browser-only runtime embedding can be mounted into a narrow hook island later."
            >
              <div class="grid gap-3 sm:grid-cols-2">
                <div class="rounded-[1.3rem] border border-black/8 bg-white/68 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                  <p class="text-[0.66rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                    Chain
                  </p>
                  <p class="mt-2 text-sm leading-6">{@agent.chain_id || "n/a"}</p>
                </div>
                <div class="rounded-[1.3rem] border border-black/8 bg-white/68 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                  <p class="text-[0.66rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                    Token
                  </p>
                  <p class="mt-2 text-sm leading-6">{@agent.token_id || "n/a"}</p>
                </div>
              </div>
              <div class="mt-4 rounded-[1.4rem] border border-dashed border-black/12 px-4 py-4 text-sm leading-7 text-slate-600 dark:border-white/12 dark:text-slate-300">
                Feature tags:
                <%= if @agent.feature_tags == [] do %>
                  none imported
                <% else %>
                  {Enum.join(@agent.feature_tags, ", ")}
                <% end %>
              </div>
            </.surface_card>

            <.surface_card
              eyebrow="Sales"
              title="Verified purchase ledger"
              copy="This rolls up only confirmed purchases. It does not expose individual buyers."
            >
              <div class="grid gap-3 sm:grid-cols-2">
                <div class="rounded-[1.3rem] border border-black/8 bg-white/68 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                  <p class="text-[0.66rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                    Verified purchases
                  </p>
                  <p class="mt-2 text-sm leading-6">
                    {get_in(@agent.seller_summary || %{}, [:verified_purchase_count]) || 0}
                  </p>
                </div>
                <div class="rounded-[1.3rem] border border-black/8 bg-white/68 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                  <p class="text-[0.66rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                    Total sales (USDC)
                  </p>
                  <p class="mt-2 text-sm leading-6">
                    {get_in(@agent.seller_summary || %{}, [:total_sales_usdc]) || "0"}
                  </p>
                </div>
              </div>
            </.surface_card>
          </section>
        <% else %>
          <section class="grid gap-4">
            <.surface_card
              eyebrow="Missing"
              title="Agent not found"
              copy="Either the import has not run yet or the slug does not exist in the new canonical table."
            >
              <.empty_state message="Run the platform import task and revisit this route." />
            </.surface_card>
          </section>
        <% end %>
      </.platform_shell>
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
