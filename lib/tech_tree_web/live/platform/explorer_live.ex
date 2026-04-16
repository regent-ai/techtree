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
  def handle_params(params, _uri, socket) do
    {:noreply, apply_params(socket, params)}
  end

  @impl true
  def handle_event("select-tile", %{"coord-key" => coord_key}, socket) do
    {:noreply, push_patch(socket, to: explorer_path(socket.assigns.path, coord_key))}
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
          next_selected = first_visible_coord_key(snapshot, path)

          {:noreply, push_patch(socket, to: explorer_path(path, next_selected))}
        end
    end
  end

  @impl true
  def handle_event("return", _params, socket) do
    path = socket.assigns.path
    next_path = Enum.drop(path, -1)
    next_selected = preferred_coord_key(socket.assigns.snapshot, next_path, List.last(path))

    {:noreply, push_patch(socket, to: explorer_path(next_path, next_selected))}
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
            copy="The first visible tile stays selected so you always have a starting point. Use drilldown and return to move between levels."
          >
            <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <%= for tile <- visible_tiles do %>
                <button
                  id={"platform-tile-#{String.replace(tile.coord_key, ":", "-")}"}
                  type="button"
                  phx-click="select-tile"
                  phx-value-coord-key={tile.coord_key}
                  class={[
                    "rounded-[1.4rem] border px-4 py-4 text-left transition hover:-translate-y-0.5",
                    if(@selected_coord_key == tile.coord_key,
                      do:
                        "border-amber-300/70 bg-amber-50/90 shadow-[0_16px_44px_-32px_rgba(217,119,6,0.45)] dark:border-amber-300/40 dark:bg-amber-200/10",
                      else:
                        "border-black/8 bg-white/70 hover:border-black/14 hover:bg-white dark:border-white/10 dark:bg-white/5 dark:hover:border-white/18 dark:hover:bg-white/10"
                    )
                  ]}
                >
                  <p class="font-display text-lg">{tile.title}</p>
                  <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                    {tile.coord_key}
                  </p>
                  <p class="mt-3 text-xs uppercase tracking-[0.18em] text-slate-500 dark:text-slate-400">
                    {tile.terrain || "unknown"}
                  </p>
                  <p
                    :if={@selected_coord_key == tile.coord_key}
                    class="mt-3 text-[0.66rem] uppercase tracking-[0.18em] text-amber-700 dark:text-amber-300"
                  >
                    Selected
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
                    Selected tile
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
              copy="Use the current path and the selected tile to keep your place when you share or reload this route."
            >
              <div class="grid gap-2">
                <p class="text-sm leading-7 text-slate-600 dark:text-slate-300">
                  {if(@path == [], do: "Root tiles", else: Enum.join(@path, " → "))}
                </p>
                <p class="text-sm leading-7 text-slate-600 dark:text-slate-300">
                  Selected: {if(selected_tile, do: selected_tile.coord_key, else: "none")}
                </p>
              </div>
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

  defp apply_params(socket, params) do
    snapshot = socket.assigns.snapshot
    path = normalize_path(snapshot, Map.get(params, "path"))
    selected = preferred_coord_key(snapshot, path, Map.get(params, "selected"))

    socket
    |> assign(:path, path)
    |> assign(:selected_coord_key, selected)
  end

  defp normalize_path(snapshot, nil), do: normalize_path(snapshot, "")

  defp normalize_path(snapshot, value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.reduce([], fn coord_key, acc ->
      next_path = acc ++ [coord_key]

      if Platform.explorer_view_tiles(snapshot, next_path) == [] do
        acc
      else
        next_path
      end
    end)
  end

  defp preferred_coord_key(snapshot, path, coord_key) do
    visible_tiles = Platform.explorer_view_tiles(snapshot, path)
    visible_coord_keys = Enum.map(visible_tiles, & &1.coord_key)

    cond do
      is_binary(coord_key) and coord_key in visible_coord_keys ->
        coord_key

      true ->
        first_visible_coord_key(snapshot, path)
    end
  end

  defp first_visible_coord_key(snapshot, path) do
    snapshot
    |> Platform.explorer_view_tiles(path)
    |> List.first()
    |> case do
      nil -> nil
      tile -> tile.coord_key
    end
  end

  defp explorer_path(path, selected_coord_key) do
    params =
      %{}
      |> maybe_put("path", if(path == [], do: nil, else: Enum.join(path, ",")))
      |> maybe_put("selected", selected_coord_key)

    ~p"/platform/explorer?#{params}"
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, _key, ""), do: params
  defp maybe_put(params, key, value), do: Map.put(params, key, value)
end
