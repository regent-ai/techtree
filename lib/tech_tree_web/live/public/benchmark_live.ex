defmodule TechTreeWeb.Public.BenchmarkLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.Benchmarks
  alias TechTree.PublicSite
  alias TechTreeWeb.PublicSiteComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Benchmark Capsule")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:detail, nil)}
  end

  @impl true
  def handle_params(%{"id" => capsule_id}, _uri, socket) do
    case Benchmarks.public_detail_page(capsule_id) do
      {:ok, detail} ->
        {:noreply,
         socket
         |> assign(:detail, detail)
         |> assign(:page_title, detail.capsule.title)}

      {:error, :capsule_not_found} ->
        {:noreply, push_navigate(socket, to: "/benchmarks")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div
      id="benchmark-detail-page"
      class="tt-public-shell"
      phx-hook="PublicSiteMotion"
      data-motion-scope="benchmark-detail"
    >
      <PublicSiteComponents.public_topbar current={:benchmarks} ios_app_url={@ios_app_url} />

      <main :if={@detail} class="tt-public-main">
        <section class="tt-public-page-hero">
          <div class="tt-public-hero-copy" data-public-reveal>
            <p class="tt-public-kicker"><PublicSiteComponents.sigil /> Benchmark capsule</p>
            <h1>{@detail.capsule.title}</h1>
            <p class="tt-public-hero-copy-text">
              {present(@detail.capsule.summary_md, @detail.capsule.question_md)}
            </p>
          </div>

          <div class="tt-public-hero-actions tt-public-hero-actions-tight" data-public-reveal>
            <.link navigate={~p"/benchmarks"} class="tt-public-secondary-button">
              Back to benchmarks
            </.link>
            <.link
              :if={@detail.capsule.source_node_id}
              navigate={~p"/tree/node/#{@detail.capsule.source_node_id}"}
              class="tt-public-secondary-button"
            >
              Open tree node
            </.link>
          </div>
        </section>

        <section
          class="tt-public-signal-strip tt-public-live-panel"
          data-public-reveal
          data-public-live-panel="benchmark-metrics"
        >
          <article
            :for={card <- @detail.cards}
            class="tt-public-signal-card tt-public-metric-card"
            data-public-metric-card={card.title}
            data-public-live-item={"benchmark-metric-#{card.title}"}
            data-public-live-revision={card.value}
          >
            <p class="tt-public-signal-label">{card.title}</p>
            <p class="tt-public-signal-value">{card.value}</p>
          </article>
        </section>

        <section class="tt-public-tree-layout">
          <div class="tt-public-tree-main">
            <section class="tt-public-tree-canvas">
              <div class="tt-public-tree-grid">
                <article class="tt-public-tree-card" data-public-reveal>
                  <div class="tt-public-tree-card-head">
                    <span class="tt-public-seed-chip">Task</span>
                    <span class="tt-public-room-chip">{labelize(@detail.capsule.domain)}</span>
                  </div>
                  <p>{@detail.capsule.question_md}</p>
                </article>

                <article class="tt-public-tree-card" data-public-reveal>
                  <div class="tt-public-tree-card-head">
                    <span class="tt-public-seed-chip">Policies</span>
                    <span class="tt-public-room-chip">
                      {labelize(@detail.capsule.ground_truth_policy)}
                    </span>
                  </div>
                  <ul class="tt-public-side-list-items">
                    <li>
                      <strong>Answer format</strong>
                      <p>{json_line(@detail.capsule.answer_format)}</p>
                    </li>
                    <li>
                      <strong>Scoring</strong>
                      <p>{json_line(@detail.capsule.scoring_policy)}</p>
                    </li>
                    <li>
                      <strong>Allowed tools</strong>
                      <p>{json_line(@detail.capsule.allowed_tools_policy)}</p>
                    </li>
                    <li>
                      <strong>Outside resources</strong>
                      <p>{json_line(@detail.capsule.external_resource_policy)}</p>
                    </li>
                  </ul>
                </article>

                <article class="tt-public-tree-card" data-public-reveal>
                  <div class="tt-public-tree-card-head">
                    <span class="tt-public-seed-chip">Versions</span>
                    <span class="tt-public-room-chip">{length(@detail.versions)} listed</span>
                  </div>
                  <ul class="tt-public-side-list-items">
                    <li
                      :for={version <- @detail.versions}
                      id={"benchmark-version-#{version.version_id}"}
                    >
                      <div class="tt-public-side-link">
                        <div>
                          <strong>{version.version_label}</strong>
                          <p
                            class="tt-public-copy-value"
                            data-copy-value={version.manifest_sha256}
                            data-copy-label="Version fingerprint"
                          >
                            {present(version.manifest_sha256, "No manifest fingerprint recorded.")}
                          </p>
                        </div>
                        <button
                          :if={version.manifest_sha256}
                          type="button"
                          class="tt-public-copy-action"
                          data-copy-button
                          data-copy-value={version.manifest_sha256}
                          data-copy-label="Version fingerprint"
                        >
                          Copy
                        </button>
                        <span>{labelize(version.version_status)}</span>
                      </div>
                    </li>
                  </ul>
                </article>

                <article class="tt-public-tree-card" data-public-reveal>
                  <div class="tt-public-tree-card-head">
                    <span class="tt-public-seed-chip">Reliability</span>
                    <span class="tt-public-room-chip">{length(@detail.reliability)} groups</span>
                  </div>
                  <%= if @detail.reliability == [] do %>
                    <div class="tt-public-empty-state">
                      No attempts have been summarized yet.
                      <.link navigate={~p"/benchmarks"} class="tt-public-inline-link">
                        Browse other capsules
                      </.link>
                      while this one fills in.
                    </div>
                  <% else %>
                    <ul class="tt-public-side-list-items">
                      <li
                        :for={entry <- @detail.reliability}
                        id={"benchmark-reliability-#{entry.summary_id}"}
                      >
                        <div class="tt-public-side-link">
                          <div>
                            <strong>{entry.harness_id}</strong>
                            <p>
                              {entry.solve_count}/{entry.attempt_count} solved across this repeat group.
                            </p>
                          </div>
                          <span>{percent(entry.solve_rate)}</span>
                        </div>
                      </li>
                    </ul>
                  <% end %>
                </article>
              </div>
            </section>
          </div>

          <aside class="tt-public-tree-side">
            <section id="benchmark-evidence" class="tt-public-side-list" data-public-reveal>
              <div class="tt-public-side-list-head">
                <h3>Evidence trail</h3>
                <p>Artifact fingerprints and review packets are listed here when they are public.</p>
              </div>
              <%= if @detail.artifacts == [] do %>
                <div class="tt-public-empty-state">
                  No public artifacts are listed yet.
                  <.link navigate={~p"/benchmarks"} class="tt-public-inline-link">
                    Browse other capsules
                  </.link>
                  for records with attached proof.
                </div>
              <% else %>
                <ul class="tt-public-side-list-items">
                  <li
                    :for={artifact <- @detail.artifacts}
                    id={"benchmark-artifact-#{artifact.artifact_id}"}
                  >
                    <div class="tt-public-side-link">
                      <div>
                        <strong>{artifact.name || labelize(artifact.kind)}</strong>
                        <p
                          class="tt-public-copy-value"
                          data-copy-value={artifact.cid || artifact.sha256 || artifact.uri}
                          data-copy-label="Artifact fingerprint"
                        >
                          {artifact.cid || artifact.sha256 || artifact.uri || "Fingerprint pending."}
                        </p>
                      </div>
                      <button
                        :if={artifact.cid || artifact.sha256 || artifact.uri}
                        type="button"
                        class="tt-public-copy-action"
                        data-copy-button
                        data-copy-value={artifact.cid || artifact.sha256 || artifact.uri}
                        data-copy-label="Artifact fingerprint"
                      >
                        Copy
                      </button>
                      <span>{labelize(artifact.visibility)}</span>
                    </div>
                  </li>
                </ul>
              <% end %>
            </section>
          </aside>
        </section>
      </main>
    </div>
    """
  end

  defp present(nil, fallback), do: present_text(fallback)
  defp present("", fallback), do: present_text(fallback)
  defp present(value, _fallback), do: present_text(value)

  defp present_text(value) when is_binary(value), do: value
  defp present_text(_value), do: "No note recorded yet."

  defp json_line(value) when value in [%{}, nil], do: "No policy details recorded yet."
  defp json_line(value), do: Jason.encode!(value)

  defp percent(nil), do: "0%"
  defp percent(value), do: "#{round(value * 100)}%"

  defp labelize(nil), do: "Unknown"

  defp labelize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
