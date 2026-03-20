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
    <div class="platform-app min-h-screen bg-[radial-gradient(circle_at_top_left,rgba(249,115,22,0.18),transparent_24%),radial-gradient(circle_at_80%_0%,rgba(56,189,248,0.18),transparent_28%),linear-gradient(180deg,#f5f1e8_0%,#ecf5ff_52%,#f4efe6_100%)] text-slate-950 dark:bg-[radial-gradient(circle_at_top_left,rgba(249,115,22,0.16),transparent_28%),radial-gradient(circle_at_82%_0%,rgba(56,189,248,0.14),transparent_30%),linear-gradient(180deg,#111723_0%,#0a1320_56%,#0d1117_100%)] dark:text-slate-50">
      <div class="mx-auto flex min-h-screen w-full max-w-[1440px] flex-col gap-4 px-3 py-3 sm:px-4 lg:flex-row lg:px-6 lg:py-5">
        <aside class="platform-panel platform-panel--nav flex w-full shrink-0 flex-col gap-4 overflow-hidden rounded-[2rem] border border-black/8 bg-white/78 p-4 shadow-[0_20px_80px_-48px_rgba(15,23,42,0.55)] backdrop-blur lg:w-[280px] dark:border-white/10 dark:bg-slate-950/68 dark:shadow-[0_20px_90px_-52px_rgba(2,6,23,0.95)]">
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

          <p class="text-sm leading-6 text-slate-600 dark:text-slate-300">
            The Phoenix cutover keeps state on the server and leaves browser-only concerns to a thin interop layer.
          </p>

          <nav class="grid gap-2" aria-label="Platform navigation">
            <%= for item <- nav_items() do %>
              <.link
                navigate={item.href}
                class={[
                  "group flex items-center justify-between rounded-2xl border px-3 py-3 text-sm transition",
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

          <div
            id="platform-auth-panel"
            phx-hook="PlatformAuth"
            data-privy-app-id={Map.get(@client_config, :privy_app_id, "")}
            class="mt-auto rounded-[1.6rem] border border-black/8 bg-black px-4 py-4 text-white dark:border-white/10 dark:bg-slate-900"
          >
            <p class="text-[0.68rem] uppercase tracking-[0.26em] text-amber-300">Auth bridge</p>
            <p class="mt-2 text-sm leading-6 text-white/78">
              Use existing Privy JWT verification for user-owned browser actions. The hook keeps this panel browser-native without turning the rest of the page into a client app.
            </p>
            <div class="mt-3 flex items-center gap-3">
              <button
                type="button"
                data-platform-auth-action="toggle"
                class="rounded-full border border-white/16 bg-white/10 px-4 py-2 text-sm transition hover:bg-white/16"
              >
                Privy Login
              </button>
              <span data-platform-auth-state class="text-xs uppercase tracking-[0.18em] text-white/56">
                idle
              </span>
            </div>
          </div>
        </aside>

        <div class="flex min-h-[80vh] min-w-0 flex-1 flex-col gap-4">
          <header class="platform-panel rounded-[2rem] border border-black/8 bg-white/72 px-5 py-5 shadow-[0_20px_80px_-48px_rgba(15,23,42,0.35)] backdrop-blur dark:border-white/10 dark:bg-slate-950/58">
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
                <div class="rounded-2xl border border-black/8 bg-white/72 px-4 py-3 dark:border-white/10 dark:bg-white/5">
                  <p class="text-[0.64rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                    State
                  </p>
                  <p class="mt-2 text-sm leading-6">
                    LiveView owns navigation, queries, and filters.
                  </p>
                </div>
                <div class="rounded-2xl border border-black/8 bg-white/72 px-4 py-3 dark:border-white/10 dark:bg-white/5">
                  <p class="text-[0.64rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                    Interop
                  </p>
                  <p class="mt-2 text-sm leading-6">
                    TypeScript hooks stay scoped to wallet, motion, and browser SDK seams.
                  </p>
                </div>
                <div class="rounded-2xl border border-black/8 bg-white/72 px-4 py-3 dark:border-white/10 dark:bg-white/5">
                  <p class="text-[0.64rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                    Cutover
                  </p>
                  <p class="mt-2 text-sm leading-6">
                    Source data moves in via a one-shot importer, not a permanent bridge.
                  </p>
                </div>
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
    <div class="rounded-[1.4rem] border border-dashed border-black/12 px-4 py-6 text-sm leading-6 text-slate-600 dark:border-white/12 dark:text-slate-300">
      {@message}
    </div>
    """
  end

  def nav_items do
    [
      %{key: "home", href: "/platform", label: "Platform", copy: "Landing + stack overview"},
      %{
        key: "explorer",
        href: "/platform/explorer",
        label: "Explorer",
        copy: "Imported tiles + frontier state"
      },
      %{
        key: "creator",
        href: "/platform/creator",
        label: "Creator",
        copy: "Hosted deployment surface"
      },
      %{key: "agents", href: "/platform/agents", label: "Agents", copy: "Imported agent catalog"},
      %{
        key: "facilitator",
        href: "/platform/facilitator",
        label: "Facilitator",
        copy: "x402 observability snapshot"
      },
      %{
        key: "moderation",
        href: "/platform/moderation",
        label: "Moderation",
        copy: "Hide content, ban actors, inspect action logs"
      },
      %{key: "names", href: "/platform/names", label: "Names", copy: "Imported name claims"},
      %{key: "redeem", href: "/platform/redeem", label: "Redeem", copy: "Redeem event history"}
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
