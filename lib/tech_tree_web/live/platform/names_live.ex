defmodule TechTreeWeb.Platform.NamesLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.PlatformComponents

  alias TechTree.Platform

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Platform Names")
     |> assign(:route_key, "names")
     |> assign(:snapshot, Platform.names_snapshot())
     |> assign(:client_config, platform_client_config())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.platform_shell
        route_key={@route_key}
        title="Names"
        kicker="Basenames"
        subtitle="Review names, credits, allowances, and recent ENS claims."
        client_config={@client_config}
      >
        <section id="platform-names-hook" class="grid gap-4 xl:grid-cols-[1fr_1fr_1fr]">
          <.surface_card
            eyebrow="Overview"
            title="Credits, allowances, and ENS claims"
            copy="See the current names snapshot in one place."
          >
            <div class="grid gap-3">
              <div class="rounded-[1.4rem] border border-black/8 bg-black/5 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                <p class="text-[0.68rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                  Available credits
                </p>
                <p class="mt-2 text-2xl leading-none">{@snapshot.available_credit_count}</p>
              </div>
              <div class="rounded-[1.4rem] border border-black/8 bg-black/5 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                <p class="text-[0.68rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                  Allowances
                </p>
                <p class="mt-2 text-2xl leading-none">{@snapshot.allowance_count}</p>
              </div>
              <div class="rounded-[1.4rem] border border-black/8 bg-black/5 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                <p class="text-[0.68rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                  ENS claims
                </p>
                <p class="mt-2 text-2xl leading-none">{@snapshot.ens_claim_count}</p>
              </div>
            </div>
          </.surface_card>

          <.surface_card
            eyebrow="Recent"
            title="Name claims"
            copy="Newest basenames appear first."
          >
            <div class="grid gap-3">
              <%= for claim <- @snapshot.recent do %>
                <div class="rounded-[1.4rem] border border-black/8 bg-white/70 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                  <p class="font-display text-lg">{claim.fqdn}</p>
                  <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                    {claim.owner_address || "n/a"}
                  </p>
                </div>
              <% end %>
            </div>
          </.surface_card>

          <.surface_card
            eyebrow="Claims"
            title="Credits and reservation data"
            copy="Review allowances, credits, and claim records together."
          >
            <div class="grid gap-3">
              <%= for credit <- @snapshot.credits do %>
                <div class="rounded-[1.4rem] border border-black/8 bg-white/70 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                  <p class="font-display text-lg">{credit.address}</p>
                  <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                    {credit.parent_name}
                  </p>
                </div>
              <% end %>

              <%= for allowance <- @snapshot.allowances do %>
                <div class="rounded-[1.4rem] border border-black/8 bg-white/70 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                  <p class="font-display text-lg">{allowance.address}</p>
                  <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                    {allowance.parent_name}
                  </p>
                </div>
              <% end %>

              <%= for claim <- @snapshot.ens_claims do %>
                <div class="rounded-[1.4rem] border border-black/8 bg-white/70 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                  <p class="font-display text-lg">{claim.fqdn}</p>
                  <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                    {claim.reservation_status} / {claim.mint_status}
                  </p>
                </div>
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
