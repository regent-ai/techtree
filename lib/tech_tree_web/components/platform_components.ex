defmodule TechTreeWeb.PlatformComponents do
  @moduledoc false
  use Phoenix.Component

  use TechTreeWeb, :verified_routes

  attr :route_key, :string, required: true
  attr :title, :string, required: true
  attr :kicker, :string, required: true
  attr :subtitle, :string, required: true
  attr :client_config, :map, default: %{}
  slot :inner_block, required: true

  def platform_shell(assigns) do
    ~H"""
    <div class="platform-app min-h-screen bg-[radial-gradient(circle_at_top_left,rgba(249,115,22,0.12),transparent_24%),radial-gradient(circle_at_84%_0%,rgba(56,189,248,0.12),transparent_28%),linear-gradient(180deg,#f1ede2_0%,#e7eef6_42%,#e9eef4_100%)] text-slate-950 dark:bg-[radial-gradient(circle_at_top_left,rgba(249,115,22,0.12),transparent_26%),radial-gradient(circle_at_82%_0%,rgba(56,189,248,0.1),transparent_30%),linear-gradient(180deg,#0f1722_0%,#0c131d_56%,#0b1018_100%)] dark:text-slate-50">
      <div class="mx-auto flex min-h-screen w-full max-w-[1440px] flex-col gap-4 px-3 py-3 sm:px-4 lg:flex-row lg:px-6 lg:py-5">
        <aside class="platform-panel platform-panel--nav flex w-full shrink-0 flex-col gap-4 overflow-hidden rounded-[1.65rem] border border-black/8 bg-white/82 p-4 shadow-[0_20px_80px_-48px_rgba(15,23,42,0.55)] backdrop-blur lg:w-[292px] dark:border-white/10 dark:bg-slate-950/72 dark:shadow-[0_20px_90px_-52px_rgba(2,6,23,0.95)]">
          <div class="flex items-center justify-between gap-3">
            <div>
              <p class="font-display text-[0.72rem] uppercase tracking-[0.28em] text-amber-600 dark:text-amber-300">
                Regent Platform
              </p>
              <h1 class="mt-2 text-2xl leading-none">{@title}</h1>
            </div>
            <div class="grid size-12 place-items-center rounded-2xl border border-black/8 bg-black text-white dark:border-white/10 dark:bg-white dark:text-slate-950">
              <span class="font-display text-sm">CX</span>
            </div>
          </div>

          <div
            id="platform-auth-panel"
            phx-hook="PlatformAuth"
            data-privy-app-id={Map.get(@client_config, :privy_app_id, "")}
            data-lazy-fallback-message="Wallet controls are unavailable right now. Reload the page or check the wallet settings."
            class="rounded-[1.35rem] border border-black/8 bg-black px-4 py-4 text-white dark:border-white/10 dark:bg-slate-900"
          >
            <p class="text-[0.68rem] uppercase tracking-[0.26em] text-amber-300">Wallet first</p>
            <p class="mt-2 text-sm leading-6 text-white/78">
              Connect a wallet before you use account-linked actions in the workspace.
            </p>
            <div class="mt-3 flex items-center gap-3">
              <button
                type="button"
                data-platform-auth-action="toggle"
                class="rounded-full border border-white/16 bg-white/10 px-4 py-2 text-sm transition hover:bg-white/16"
              >
                Connect wallet
              </button>
              <button
                type="button"
                data-platform-auth-action="disconnect"
                class="hidden rounded-full border border-white/16 px-4 py-2 text-sm text-white/82 transition hover:bg-white/10"
              >
                Disconnect
              </button>
              <span data-platform-auth-state class="text-xs uppercase tracking-[0.18em] text-white/56">
                Idle
              </span>
            </div>
          </div>

          <p class="text-sm leading-6 text-slate-600 dark:text-slate-300">
            Move through platform previews, inspect imported records, and keep operator actions grouped in one place.
          </p>

          <nav class="grid gap-2" aria-label="Platform navigation">
            <%= for item <- nav_items() do %>
              <.link
                navigate={item.href}
                class={[
                  "group flex items-center justify-between rounded-[1.25rem] border px-3 py-3 text-sm transition",
                  nav_link_class(@route_key, item.key)
                ]}
              >
                <span class="flex flex-col">
                  <span class="font-display text-[0.8rem] uppercase tracking-[0.18em]">
                    {item.label}
                  </span>
                  <span class="mt-1 text-xs text-slate-500 group-hover:text-current dark:text-slate-400">
                    {item.copy}
                  </span>
                </span>
                <span class="text-lg opacity-55 transition group-hover:translate-x-1 group-hover:opacity-100">
                  →
                </span>
              </.link>
            <% end %>
          </nav>
        </aside>

        <div class="flex min-h-[80vh] min-w-0 flex-1 flex-col gap-4">
          <header class="platform-panel rounded-[1.65rem] border border-black/8 bg-white/76 px-5 py-5 shadow-[0_20px_80px_-48px_rgba(15,23,42,0.35)] backdrop-blur dark:border-white/10 dark:bg-slate-950/62">
            <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
              <div class="max-w-3xl">
                <p class="font-display text-[0.72rem] uppercase tracking-[0.32em] text-amber-600 dark:text-amber-300">
                  {@kicker}
                </p>
                <h2 class="mt-3 text-4xl leading-none sm:text-5xl">{@title}</h2>
                <p class="mt-4 max-w-2xl text-sm leading-7 text-slate-600 dark:text-slate-300">
                  {@subtitle}
                </p>
              </div>
              <div class="grid gap-2 sm:grid-cols-3">
                <%= for item <- workspace_links() do %>
                  <.link
                    navigate={item.href}
                    class="rounded-[1.2rem] border border-black/8 bg-white/72 px-4 py-3 transition hover:border-black/14 hover:bg-white dark:border-white/10 dark:bg-white/5 dark:hover:border-white/18 dark:hover:bg-white/10"
                  >
                    <p class="text-[0.64rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                      {item.label}
                    </p>
                    <p class="mt-2 text-sm leading-6">
                      {item.copy}
                    </p>
                  </.link>
                <% end %>
              </div>
            </div>
          </header>

          <main class="grid min-w-0 flex-1 gap-4">
            {render_slot(@inner_block)}
          </main>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :tone, :string, default: "default"
  attr :copy, :string, default: nil

  def stat_card(assigns) do
    ~H"""
    <article class={[
      "rounded-[1.75rem] border px-5 py-5 shadow-[0_18px_60px_-42px_rgba(15,23,42,0.4)] backdrop-blur",
      tone_class(@tone)
    ]}>
      <p class="text-[0.68rem] uppercase tracking-[0.26em] text-slate-500 dark:text-slate-400">
        {@label}
      </p>
      <p class="mt-4 text-3xl leading-none">{@value}</p>
      <p :if={@copy} class="mt-3 text-sm leading-6 text-slate-600 dark:text-slate-300">{@copy}</p>
    </article>
    """
  end

  attr :title, :string, required: true
  attr :eyebrow, :string, required: true
  attr :copy, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def surface_card(assigns) do
    ~H"""
    <section class={[
      "rounded-[2rem] border border-black/8 bg-white/72 p-5 shadow-[0_20px_80px_-48px_rgba(15,23,42,0.36)] backdrop-blur dark:border-white/10 dark:bg-slate-950/58",
      @class
    ]}>
      <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div class="max-w-2xl">
          <p class="font-display text-[0.68rem] uppercase tracking-[0.28em] text-amber-600 dark:text-amber-300">
            {@eyebrow}
          </p>
          <h3 class="mt-3 text-2xl leading-none sm:text-3xl">{@title}</h3>
          <p class="mt-3 text-sm leading-7 text-slate-600 dark:text-slate-300">{@copy}</p>
        </div>
      </div>
      <div class="mt-5">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex rounded-full border px-3 py-1 text-[0.66rem] uppercase tracking-[0.22em]",
      status_class(@status)
    ]}>
      {@status}
    </span>
    """
  end

  attr :message, :string, required: true

  def empty_state(assigns) do
    ~H"""
    <div class="rounded-[1.4rem] border border-dashed border-black/12 bg-white/72 px-4 py-5 text-sm leading-6 text-slate-600 shadow-[0_18px_50px_-38px_rgba(15,23,42,0.28)] dark:border-white/12 dark:bg-slate-950/52 dark:text-slate-300">
      <p class="font-display text-[0.68rem] uppercase tracking-[0.28em] text-amber-600 dark:text-amber-300">
        Nothing here yet
      </p>
      <p class="mt-2">{@message}</p>
    </div>
    """
  end

  def nav_items do
    [
      %{
        key: "home",
        href: "/platform",
        label: "Platform",
        copy: "Overview and quick entry points"
      },
      %{
        key: "explorer",
        href: "/platform/explorer",
        label: "Explorer",
        copy: "Browse frontier tiles and drill into details"
      },
      %{
        key: "creator",
        href: "/platform/creator",
        label: "Creator",
        copy: "Review launch candidates"
      },
      %{
        key: "agents",
        href: "/platform/agents",
        label: "Agents",
        copy: "Search the agent catalog"
      },
      %{
        key: "facilitator",
        href: "/platform/facilitator",
        label: "Facilitator",
        copy: "Check service reachability"
      },
      %{
        key: "moderation",
        href: "/platform/moderation",
        label: "Moderation",
        copy: "Hide content, ban actors, inspect action logs"
      },
      %{
        key: "names",
        href: "/platform/names",
        label: "Names",
        copy: "Review names, credits, and claims"
      },
      %{
        key: "redeem",
        href: "/platform/redeem",
        label: "Redeem",
        copy: "Review redemption history"
      }
    ]
  end

  def workspace_links do
    [
      %{href: "/", label: "Public home", copy: "Return to the guided front door."},
      %{href: "/tree", label: "Explore tree", copy: "Open the public tree."},
      %{href: "/learn/bbh-train", label: "BBH guide", copy: "Jump into the guided BBH path."}
    ]
  end

  def platform_client_config do
    privy_config = Application.get_env(:tech_tree, :privy, [])
    %{privy_app_id: Keyword.get(privy_config, :app_id, "")}
  end

  defp nav_link_class(current, key) when current == key do
    "border-black/12 bg-black text-white dark:border-white/14 dark:bg-white dark:text-slate-950"
  end

  defp nav_link_class(_current, _key) do
    "border-black/8 bg-white/60 hover:border-black/14 hover:bg-white dark:border-white/10 dark:bg-white/5 dark:hover:border-white/18 dark:hover:bg-white/10"
  end

  defp tone_class("signal"),
    do: "border-amber-300/50 bg-amber-50/90 dark:border-amber-300/18 dark:bg-amber-200/6"

  defp tone_class("ocean"),
    do: "border-sky-300/45 bg-sky-50/92 dark:border-sky-300/18 dark:bg-sky-200/6"

  defp tone_class(_default),
    do: "border-black/8 bg-white/72 dark:border-white/10 dark:bg-slate-950/58"

  defp status_class(status) when status in ["active", "ready", "claimed", "indexed"] do
    "border-emerald-400/40 bg-emerald-500/12 text-emerald-700 dark:text-emerald-300"
  end

  defp status_class(status) when status in ["draft", "queued", "pending"] do
    "border-amber-400/40 bg-amber-500/12 text-amber-700 dark:text-amber-300"
  end

  defp status_class(status) when status in ["failed", "degraded", "blocked"] do
    "border-rose-400/40 bg-rose-500/12 text-rose-700 dark:text-rose-300"
  end

  defp status_class(_status) do
    "border-black/10 bg-black/5 text-slate-700 dark:border-white/12 dark:bg-white/5 dark:text-slate-200"
  end
end
