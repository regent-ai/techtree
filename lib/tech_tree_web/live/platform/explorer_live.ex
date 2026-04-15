defmodule TechTreeWeb.Platform.ExplorerLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.PlatformComponents

  alias TechTree.Platform

  @impl true
  def mount(_params, _session, socket) do
    snapshot = Platform.explorer_snapshot()

    {:ok,
     socket
     |> assign(:page_title, "Platform Explorer")
     |> assign(:route_key, "explorer")
     |> assign(:snapshot, snapshot)
     |> assign(:path, [])
     |> assign(:selected_coord_key, nil)
     |> assign(:client_config, platform_client_config())}
  end

  @impl true
  def handle_event("select-tile", %{"coord-key" => coord_key}, socket) do
    {:noreply, assign(socket, :selected_coord_key, coord_key)}
  end

  @impl true
  def handle_event("drilldown", _params, socket) do
    snapshot = socket.assigns.snapshot

    case current_selected_tile(snapshot, socket.assigns.selected_coord_key) do
      nil ->
        {:noreply, socket}

      tile ->
        if Platform.explorer_child_count(snapshot, tile.coord_key) == 0 do
          {:noreply, socket}
        else
          path = socket.assigns.path ++ [tile.coord_key]

          {:noreply,
           socket
           |> assign(:path, path)
           |> assign(:selected_coord_key, tile.coord_key)}
        end
    end
  end

  @impl true
  def handle_event("return", _params, socket) do
    path = socket.assigns.path
    next_path = Enum.drop(path, -1)

    {:noreply,
     socket
     |> assign(:path, next_path)
     |> assign(:selected_coord_key, List.last(next_path))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.platform_shell
        route_key={@route_key}
        title="Explorer"
        kicker="World Map"
        subtitle="Browse frontier tiles, open details, and move deeper one layer at a time."
        client_config={@client_config}
      >
        <% visible_tiles = Platform.explorer_view_tiles(@snapshot, @path) %>
        <% selected_tile = current_selected_tile(@snapshot, @selected_coord_key) %>

        <section class="grid gap-4 xl:grid-cols-[1.1fr_0.9fr]">
          <.surface_card
            eyebrow="Tiles"
            title="Imported frontier"
            copy="Click a tile to open the modal. Use drilldown and return to move between levels."
          >
            <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <%= for tile <- visible_tiles do %>
                <button
                  id={"platform-tile-#{String.replace(tile.coord_key, ":", "-")}"}
                  type="button"
                  phx-click="select-tile"
                  phx-value-coord-key={tile.coord_key}
                  class="rounded-[1.4rem] border border-black/8 bg-white/70 px-4 py-4 text-left transition hover:-translate-y-0.5 hover:border-black/14 hover:bg-white dark:border-white/10 dark:bg-white/5 dark:hover:border-white/18 dark:hover:bg-white/10"
                >
                  <p class="font-display text-lg">{tile.title}</p>
                  <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                    {tile.coord_key}
                  </p>
                  <p class="mt-3 text-xs uppercase tracking-[0.18em] text-slate-500 dark:text-slate-400">
                    {tile.terrain || "unknown"}
                  </p>
                </button>
              <% end %>
            </div>
          </.surface_card>

          <div class="grid gap-4">
            <section
              id="platform-explorer-modal"
              class="rounded-[2rem] border border-black/8 bg-white/72 p-5 shadow-[0_20px_80px_-48px_rgba(15,23,42,0.36)] backdrop-blur dark:border-white/10 dark:bg-slate-950/58"
            >
              <div class="flex items-start justify-between gap-4">
                <div>
                  <p class="font-display text-[0.68rem] uppercase tracking-[0.28em] text-amber-600 dark:text-amber-300">
                    Modal
                  </p>
                  <h3 class="mt-3 text-2xl leading-none sm:text-3xl">
                    {if(selected_tile, do: selected_tile.title, else: "Select a tile")}
                  </h3>
                </div>

                <button
                  :if={length(@path) > 0}
                  id="platform-explorer-return"
                  type="button"
                  phx-click="return"
                  class="rounded-full border border-black/10 bg-black px-4 py-2 text-sm text-white transition hover:bg-black/90 dark:border-white/10 dark:bg-white dark:text-slate-950"
                >
                  Return
                </button>
              </div>

              <div :if={selected_tile} class="mt-5 grid gap-3">
                <div class="rounded-[1.4rem] border border-black/8 bg-black/5 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                  <p class="text-[0.68rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                    Coordinates
                  </p>
                  <p class="mt-2 text-sm leading-6">{selected_tile.coord_key}</p>
                </div>

                <div class="rounded-[1.4rem] border border-black/8 bg-black/5 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                  <p class="text-[0.68rem] uppercase tracking-[0.22em] text-slate-500 dark:text-slate-400">
                    Summary
                  </p>
                  <p class="mt-2 text-sm leading-7">
                    {selected_tile.summary || "No summary imported yet."}
                  </p>
                </div>

                <button
                  :if={Platform.explorer_child_count(@snapshot, selected_tile.coord_key) > 0}
                  id="platform-explorer-action-drilldown"
                  type="button"
                  phx-click="drilldown"
                  class="rounded-full border border-black/10 bg-amber-500 px-4 py-2 text-sm text-white transition hover:bg-amber-600 dark:border-amber-400/20"
                >
                  Drill down
                </button>
              </div>
            </section>

            <.surface_card
              eyebrow="Path"
              title="Current drilldown"
              copy="Track where you are as you move deeper into the frontier."
            >
              <p class="text-sm leading-7 text-slate-600 dark:text-slate-300">
                {if(@path == [], do: "Root tiles", else: Enum.join(@path, " → "))}
              </p>
            </.surface_card>
          </div>
        </section>
      </.platform_shell>
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  defp current_selected_tile(_snapshot, nil), do: nil

  defp current_selected_tile(snapshot, coord_key) do
    Platform.explorer_tile(snapshot, coord_key)
  end
end
