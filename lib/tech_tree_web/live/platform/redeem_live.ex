defmodule TechTreeWeb.Platform.RedeemLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.PlatformComponents

  alias TechTree.Platform

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Platform Redeem")
     |> assign(:route_key, "redeem")
     |> assign(:snapshot, Platform.redeem_snapshot())
     |> assign(:client_config, platform_client_config())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.platform_shell
        route_key={@route_key}
        title="Redeem"
        kicker="Claims"
        subtitle="Review imported claim history here, then jump into the next route you need."
        client_config={@client_config}
      >
        <section id="platform-redeem-hook" class="grid gap-4">
          <.surface_card
            eyebrow="Ledger"
            title="Redeem claims"
            copy="Source collection history is surfaced directly from the platform tables, with the next route one click away."
          >
            <%= if @snapshot.claims == [] do %>
              <div class="grid gap-3">
                <.empty_state message="No redeem claims have been imported yet. Return to Platform or open the names route if you need a nearby review surface." />
                <div class="flex flex-wrap gap-2">
                  <.link navigate="/platform/names" class="btn fp-command-secondary">
                    Open Names
                  </.link>
                  <.link navigate="/platform" class="btn fp-command-secondary">
                    Back to Platform
                  </.link>
                </div>
              </div>
            <% else %>
              <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
                <%= for claim <- @snapshot.claims do %>
                  <article class="rounded-[1.4rem] border border-black/8 bg-white/70 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                    <p class="font-display text-lg">{claim.source_collection}</p>
                    <p class="mt-2 break-all text-sm leading-6 text-slate-600 dark:text-slate-300">
                      {claim.wallet_address}
                    </p>
                    <p class="mt-3 text-xs uppercase tracking-[0.18em] text-slate-500 dark:text-slate-400">
                      {claim.status}
                    </p>
                  </article>
                <% end %>
              </div>

              <div class="mt-4 flex flex-wrap gap-2">
                <.link navigate="/platform/names" class="btn fp-command-secondary">
                  Open Names
                </.link>
                <.link navigate="/platform" class="btn fp-command-secondary">
                  Back to Platform
                </.link>
              </div>
            <% end %>
          </.surface_card>
        </section>
      </.platform_shell>
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
