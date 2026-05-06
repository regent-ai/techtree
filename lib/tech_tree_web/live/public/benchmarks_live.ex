defmodule TechTreeWeb.Public.BenchmarksLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.Benchmarks
  alias TechTree.PublicSite
  alias TechTreeWeb.PublicSiteComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Benchmarks")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:page, empty_page())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :page, Benchmarks.public_index_page(params))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div
      id="benchmarks-page"
      class="tt-public-shell"
      phx-hook="PublicSiteMotion"
      data-motion-scope="benchmarks"
    >
      <PublicSiteComponents.public_topbar current={:benchmarks} ios_app_url={@ios_app_url} />

      <main class="tt-public-main">
        <section class="tt-public-page-hero">
          <div class="tt-public-hero-copy" data-public-reveal>
            <p class="tt-public-kicker"><PublicSiteComponents.sigil /> Benchmark capsules</p>
            <h1>Tasks, attempts, reviews, and reliability in one place.</h1>
            <p class="tt-public-hero-copy-text">
              Browse capsules by field, inspect the evidence trail, and see whether a method
              solves the task once or keeps solving it across repeated attempts.
            </p>
          </div>

          <div class="tt-public-hero-actions tt-public-hero-actions-tight" data-public-reveal>
            <.link navigate={~p"/bbh/wall"} class="tt-public-secondary-button">Open BBH Wall</.link>
            <.link navigate={~p"/science-tasks"} class="tt-public-secondary-button">
              Open Science Tasks
            </.link>
          </div>
        </section>

        <section class="tt-public-tree-layout">
          <div class="tt-public-tree-main">
            <section class="tt-public-tree-canvas">
              <div class="tt-public-side-list-head">
                <h3>Capsule board</h3>
                <p>
                  Filter the public benchmark set, then open any capsule for its policies,
                  attempts, reviews, and evidence.
                </p>
              </div>

              <div class="tt-public-chip-row" data-public-reveal>
                <.filter_chip
                  :for={{domain, label} <- @page.domains}
                  href={
                    benchmarks_href(@page.filters, %{
                      domain: if(domain == "all", do: nil, else: domain)
                    })
                  }
                  active={(@page.filters.domain || "all") == domain}
                >
                  {label}
                  <span :if={domain != "all"}>({Map.get(@page.counts_by_domain, domain, 0)})</span>
                </.filter_chip>
              </div>

              <div :if={@page.fields != []} class="tt-public-chip-row" data-public-reveal>
                <.filter_chip
                  href={benchmarks_href(@page.filters, %{field: nil})}
                  active={is_nil(@page.filters.field)}
                >
                  All fields
                </.filter_chip>
                <.filter_chip
                  :for={field <- @page.fields}
                  href={benchmarks_href(@page.filters, %{field: field})}
                  active={@page.filters.field == field}
                >
                  {field}
                </.filter_chip>
              </div>

              <%= if @page.capsules == [] do %>
                <div class="tt-public-empty-state" data-public-reveal>
                  No benchmark capsules match these filters yet.
                </div>
              <% else %>
                <div class="tt-public-tree-grid">
                  <article
                    :for={capsule <- @page.capsules}
                    id={"benchmark-capsule-#{capsule.capsule_id}"}
                    class="tt-public-tree-card"
                    data-public-reveal
                    data-public-live-item={capsule.capsule_id}
                  >
                    <div class="tt-public-tree-card-head">
                      <span class="tt-public-seed-chip">{domain_label(capsule.domain)}</span>
                      <span class="tt-public-room-chip">{capsule.reliability_label}</span>
                    </div>
                    <h3>{capsule.title}</h3>
                    <p>{present(capsule.summary_md, capsule.question_md)}</p>
                    <div class="tt-public-chip-row">
                      <span class="tt-public-room-chip">{capsule.field_label}</span>
                      <span class="tt-public-room-chip">{capsule.difficulty_label}</span>
                      <span class="tt-public-room-chip">{capsule.attempt_label}</span>
                    </div>
                    <div class="tt-public-card-actions">
                      <.link navigate={capsule.href} class="tt-public-card-link is-secondary">
                        Inspect capsule
                      </.link>
                    </div>
                  </article>
                </div>
              <% end %>
            </section>
          </div>

          <aside class="tt-public-tree-side">
            <section id="benchmark-notes" class="tt-public-side-list" data-public-reveal>
              <div class="tt-public-side-list-head">
                <h3>What to inspect</h3>
              </div>
              <ul class="tt-public-side-list-items">
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Task and policy</strong>
                      <p>
                        The instructions, answer format, scoring notes, and allowed tools stay together.
                      </p>
                    </div>
                  </div>
                </li>
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Repeated attempts</strong>
                      <p>
                        Reliability shows whether a method keeps working, not just whether it won once.
                      </p>
                    </div>
                  </div>
                </li>
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Reviews and evidence</strong>
                      <p>
                        Capsules show the reviews and artifact fingerprints that support each result.
                      </p>
                    </div>
                  </div>
                </li>
              </ul>
            </section>
          </aside>
        </section>
      </main>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp filter_chip(assigns) do
    ~H"""
    <.link navigate={@href} class={["tt-public-room-chip", @active && "is-active"]}>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp benchmarks_href(filters, changes) do
    filters
    |> Map.merge(changes)
    |> Map.take([:domain, :field, :status, :difficulty])
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> case do
      [] -> "/benchmarks"
      query -> "/benchmarks?" <> URI.encode_query(query)
    end
  end

  defp present(nil, fallback), do: trim_text(fallback)
  defp present("", fallback), do: trim_text(fallback)
  defp present(value, _fallback), do: trim_text(value)

  defp trim_text(value) when is_binary(value) do
    if String.length(value) > 180, do: String.slice(value, 0, 180) <> "...", else: value
  end

  defp trim_text(_value), do: "No summary recorded yet."

  defp domain_label(nil), do: "Other"

  defp domain_label(domain) do
    domain
    |> String.replace("_", " ")
    |> String.upcase()
  end

  defp empty_page do
    %{
      filters: %{domain: nil, field: nil, status: nil, difficulty: nil},
      capsules: [],
      domains: [{"all", "All"}],
      fields: [],
      statuses: [],
      difficulties: [],
      counts_by_domain: %{}
    }
  end
end
