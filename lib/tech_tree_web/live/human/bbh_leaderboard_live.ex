defmodule TechTreeWeb.Human.BbhLeaderboardLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.HumanComponents

  alias TechTree.BBH.Presentation

  @refresh_interval_ms 4_000

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "BBH Wall")
      |> assign(:split, "benchmark")
      |> assign(:selected_capsule_id, params["focus"] || params["capsule_id"])

    if connected?(socket) do
      Process.send_after(self(), :refresh_board, @refresh_interval_ms)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    focus = params["focus"] || params["capsule_id"] || socket.assigns.selected_capsule_id

    {:noreply,
     socket
     |> assign_page(
       Presentation.leaderboard_page(%{
         selected_capsule_id: focus
       })
     )}
  end

  @impl true
  def handle_event("select-capsule", %{"capsule_id" => capsule_id}, socket) do
    {:noreply, push_patch(socket, to: wall_path(capsule_id))}
  end

  @impl true
  def handle_info(:refresh_board, socket) do
    page =
      Presentation.leaderboard_page(%{
        selected_capsule_id: socket.assigns.selected_capsule_id
      })

    if connected?(socket) do
      Process.send_after(self(), :refresh_board, @refresh_interval_ms)
    end

    {:noreply, assign_page(socket, page)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <main id="bbh-leaderboard-page" class="hu-page bbh-page" phx-hook="HumanMotion">
      <div class="hu-shell bbh-shell">
        <.human_header
          kicker="BBH Py"
          title="Wall board"
          subtitle="Practice, Proving, and Challenge stay wall-first. The official board sections start empty in this beta cut, and the pinned drilldown survives refresh."
        >
          <:actions>
            <span class="bbh-chip">Practice: {@lane_counts.practice}</span>
            <span class="bbh-chip">Proving: {@lane_counts.proving}</span>
            <span class="bbh-chip">Challenge: {@lane_counts.challenge}</span>
            <span class="bbh-chip">--lane climb / benchmark / challenge</span>
            <span class="bbh-chip bbh-chip-official">Pinned focus survives refresh</span>
          </:actions>
        </.human_header>

        <section class="bbh-wall-shell">
          <div class="bbh-wall-stage">
            <.human_section id="bbh-capsule-wall" title="Wall board">
              <div class="bbh-wall-hero" data-motion="reveal">
                <div class="bbh-wall-hero-copy">
                  <p class="bbh-wall-kicker">Three-lane wall</p>
                  <h2 class="bbh-wall-title">
                    Practice, Proving, and Challenge stay visible before the ledger.
                  </h2>
                  <p class="bbh-wall-note">
                    Practice is public climb work, Proving is benchmark work, and Challenge is the
                    public reviewed frontier lane. Route setters keep Challenge fresh in public,
                    while the official board sections stay intentionally empty until the later
                    verification update.
                  </p>
                </div>

                <dl class="bbh-wall-metrics">
                  <div class="bbh-wall-metric">
                    <dt>Practice</dt>
                    <dd>{@lane_counts.practice}</dd>
                  </div>
                  <div class="bbh-wall-metric">
                    <dt>Proving</dt>
                    <dd>{@lane_counts.proving}</dd>
                  </div>
                  <div class="bbh-wall-metric">
                    <dt>Challenge</dt>
                    <dd>{@lane_counts.challenge}</dd>
                  </div>
                  <div class="bbh-wall-metric">
                    <dt>Top validated</dt>
                    <dd>{Float.round(@top_score, 1)}%</dd>
                  </div>
                </dl>
              </div>

              <div class="bbh-wall-caption">
                <span class="bbh-chip">auto: --lane climb</span>
                <span class="bbh-chip">auto: --lane benchmark</span>
                <span class="bbh-chip">auto: --lane challenge</span>
                <span class="bbh-chip">manual: --capsule &lt;capsule_id&gt;</span>
                <span class="bbh-chip bbh-chip-official">selected capsule stays pinned</span>
              </div>

              <div id="bbh-wall-grid" class="bbh-wall-grid" phx-hook="BbhCapsuleWall">
                <%= for lane <- @lane_sections do %>
                  <article id={"bbh-lane-#{lane.key}"} class={["bbh-lane-panel", "is-#{lane.key}"]}>
                    <div class="bbh-lane-header" data-motion="reveal">
                      <div>
                        <p class="bbh-rank">{lane.operator_tag}</p>
                        <h3 class="bbh-lane-title">{lane.label}</h3>
                      </div>
                      <span class="bbh-chip">{lane.count} capsules</span>
                    </div>

                    <p class="bbh-lane-copy">{lane.copy}</p>

                    <div class="bbh-lane-capsules">
                      <%= if lane.capsules == [] do %>
                        <div class="bbh-lane-empty" data-motion="reveal">
                          <p>No capsules are visible in {lane.label} yet.</p>
                        </div>
                      <% else %>
                        <%= for capsule <- lane.capsules do %>
                          <button
                            id={"bbh-capsule-#{capsule.capsule_id}"}
                            type="button"
                            phx-click="select-capsule"
                            phx-value-capsule_id={capsule.capsule_id}
                            class={[
                              "bbh-capsule",
                              capsule.layout_offset? && "is-offset",
                              capsule.is_hot && "is-hot",
                              capsule.route_maturity == :new && "is-new",
                              capsule.route_maturity == :active && "is-active",
                              capsule.route_maturity == :crowded && "is-crowded",
                              capsule.route_maturity == :saturated && "is-saturated",
                              @selected_capsule_id == capsule.capsule_id && "is-selected"
                            ]}
                            style={"--bbh-score: #{capsule.score_percent}; --bbh-validated-score: #{capsule.validated_percent};"}
                            data-capsule-id={capsule.capsule_id}
                            data-lane={capsule.operator_lane_tag}
                            data-last-event-kind={to_string(capsule.last_event_kind)}
                            data-last-event-at={
                              capsule.last_event_at &&
                                DateTime.to_unix(capsule.last_event_at, :millisecond)
                            }
                            data-active-agents={capsule.active_agent_count}
                            data-best-score={capsule.best_score || 0.0}
                            data-best-validated-score={capsule.best_validated_score || 0.0}
                            data-route-maturity={to_string(capsule.route_maturity)}
                            data-motion="reveal"
                          >
                            <span class="bbh-capsule-flash" data-bbh-motion-layer="flash"></span>
                            <span class="bbh-capsule-ring" data-bbh-motion-layer="ring"></span>
                            <span class="bbh-capsule-core">
                              <span class="bbh-capsule-badge">{capsule.lane_label}</span>
                              <span class="bbh-capsule-title">{capsule.title}</span>
                              <span class="bbh-capsule-score">{capsule.best_score_label}</span>
                              <span class="bbh-capsule-score-label">{capsule.best_state_label}</span>
                              <span class="bbh-capsule-footer">
                                <span>{outline_label(capsule.route_maturity)}</span>
                                <span>{capsule.active_agent_count} active</span>
                                <span>{capsule.freshness_label}</span>
                                <%= if capsule.certificate_status && capsule.certificate_status != "none" do %>
                                  <span>cert {capsule.certificate_status}</span>
                                <% end %>
                                <%= if capsule.review_open_count > 0 do %>
                                  <span>{capsule.review_open_count} review open</span>
                                <% end %>
                                <%= if capsule.challenge_status do %>
                                  <span>{capsule.challenge_status}</span>
                                <% end %>
                              </span>
                            </span>
                            <span class="bbh-capsule-pips">
                              <%= for _pip <- 1..max(capsule.pip_count, 1) do %>
                                <span class="bbh-capsule-pip"></span>
                              <% end %>
                            </span>
                          </button>
                        <% end %>
                      <% end %>
                    </div>
                  </article>
                <% end %>
              </div>
            </.human_section>
          </div>

          <div class="bbh-wall-sidebar">
            <.human_section id="bbh-wall-drilldown" title="Pinned drilldown">
              <%= if @drilldown_capsule do %>
                <article id={"bbh-drilldown-#{@drilldown_capsule.capsule_id}"} class="bbh-drilldown">
                  <div class="bbh-drilldown-header">
                    <div>
                      <p class="bbh-rank">{@drilldown_capsule.badge_kind}</p>
                      <h2 class="bbh-name">{@drilldown_capsule.title}</h2>
                    </div>
                    <span class="bbh-chip">{@drilldown_capsule.best_state_label}</span>
                  </div>

                  <p class="bbh-drilldown-copy bbh-drilldown-pin-note">
                    Pinned focus survives refresh and keeps its place while the wall keeps moving.
                  </p>

                  <dl class="bbh-drilldown-stats">
                    <div>
                      <dt>Active agents</dt>
                      <dd>{@drilldown_capsule.active_agent_count}</dd>
                    </div>
                    <div>
                      <dt>Runs</dt>
                      <dd>{@drilldown_capsule.run_count}</dd>
                    </div>
                    <div>
                      <dt>Lane</dt>
                      <dd>{@drilldown_capsule.lane_label}</dd>
                    </div>
                    <div>
                      <dt>Status</dt>
                      <dd>{@drilldown_capsule.best_state_label}</dd>
                    </div>
                    <div>
                      <dt>Route maturity</dt>
                      <dd>{outline_label(@drilldown_capsule.route_maturity)}</dd>
                    </div>
                    <div>
                      <dt>Freshness</dt>
                      <dd>{@drilldown_capsule.freshness_label}</dd>
                    </div>
                  </dl>

                  <div class="bbh-drilldown-block">
                    <h3>Current best genome</h3>
                    <%= if @drilldown_capsule.current_best_genome do %>
                      <p class="bbh-drilldown-copy">
                        {@drilldown_capsule.current_best_genome.name}
                      </p>
                      <p class="bbh-drilldown-meta">
                        {@drilldown_capsule.current_best_genome.model} · {@drilldown_capsule.current_best_genome.router}
                      </p>
                    <% else %>
                      <p class="bbh-drilldown-copy">No runs on this capsule yet.</p>
                    <% end %>
                  </div>

                  <div class="bbh-drilldown-block">
                    <h3>Current best run</h3>
                    <%= if @drilldown_capsule.current_best_run do %>
                      <.link
                        navigate={~p"/bbh/runs/#{@drilldown_capsule.current_best_run.id}"}
                        class="bbh-run-link"
                      >
                        <span>{@drilldown_capsule.current_best_run.score_label}</span>
                        <span class="bbh-run-link-meta">
                          {@drilldown_capsule.current_best_run.review_state}
                        </span>
                      </.link>
                    <% else %>
                      <p class="bbh-drilldown-copy">Waiting for the first climb.</p>
                    <% end %>
                  </div>

                  <div class="bbh-drilldown-block">
                    <h3>Latest validated run</h3>
                    <%= if @drilldown_capsule.latest_validated_run do %>
                      <.link
                        navigate={~p"/bbh/runs/#{@drilldown_capsule.latest_validated_run.id}"}
                        class="bbh-run-link"
                      >
                        <span>{@drilldown_capsule.latest_validated_run.score_label}</span>
                        <span class="bbh-run-link-meta">
                          {@drilldown_capsule.latest_validated_run.review_state}
                        </span>
                      </.link>
                    <% else %>
                      <p class="bbh-drilldown-copy">No validated public route run yet.</p>
                    <% end %>
                  </div>

                  <%= if @drilldown_capsule.challenge_status do %>
                    <div class="bbh-drilldown-block">
                      <h3>Challenge route state</h3>
                      <p class="bbh-drilldown-copy">{@drilldown_capsule.challenge_status}</p>
                      <p class="bbh-drilldown-meta">
                        {@drilldown_capsule.challenge_attempts} attempts
                        <%= if @drilldown_capsule.publication_age_label do %>
                          · published {@drilldown_capsule.publication_age_label}
                        <% end %>
                      </p>
                    </div>
                  <% end %>

                  <div class="bbh-drilldown-block">
                    <h3>Certificate</h3>
                    <p class="bbh-drilldown-copy">
                      {(@drilldown_capsule.certificate_status || "none")
                      |> to_string()
                      |> String.replace("_", " ")}
                    </p>
                    <p class="bbh-drilldown-meta">
                      <%= if @drilldown_capsule.certificate_review_id do %>
                        review {@drilldown_capsule.certificate_review_id}
                      <% else %>
                        no certificate review yet
                      <% end %>
                      <%= if @drilldown_capsule.certificate_expires_at do %>
                        · expires {@drilldown_capsule.certificate_expires_at}
                      <% end %>
                    </p>
                  </div>

                  <div class="bbh-drilldown-block">
                    <h3>Review queue</h3>
                    <%= if @drilldown_capsule.review_open_count > 0 do %>
                      <p class="bbh-drilldown-copy">
                        {@drilldown_capsule.review_open_count} review request(s) open.
                      </p>
                      <p class="bbh-drilldown-meta">{@drilldown_capsule.review_claim_hint}</p>
                    <% else %>
                      <p class="bbh-drilldown-copy">No public review requests are open.</p>
                    <% end %>
                  </div>

                  <div class="bbh-drilldown-block">
                    <h3>Active agents</h3>
                    <%= if @drilldown_capsule.active_agents == [] do %>
                      <p class="bbh-drilldown-copy">No recent active agents on this capsule.</p>
                    <% else %>
                      <ul class="bbh-chip-list">
                        <%= for agent <- @drilldown_capsule.active_agents do %>
                          <li><span class="bbh-chip">{agent.label}</span></li>
                        <% end %>
                      </ul>
                    <% end %>
                  </div>

                  <div class="bbh-drilldown-block">
                    <h3>Latest artifact notebook and verdict</h3>
                    <dl class="bbh-drilldown-files">
                      <div>
                        <dt>Notebook</dt>
                        <dd>{@drilldown_capsule.latest_artifact.notebook_ref || "n/a"}</dd>
                      </div>
                      <div>
                        <dt>Verdict</dt>
                        <dd>{@drilldown_capsule.latest_artifact.verdict_ref || "n/a"}</dd>
                      </div>
                    </dl>
                  </div>

                  <div class="bbh-drilldown-block">
                    <h3>Recent runs</h3>
                    <ul class="bbh-run-list">
                      <%= for run <- @drilldown_capsule.recent_runs do %>
                        <li>
                          <.link navigate={~p"/bbh/runs/#{run.id}"} class="bbh-run-link">
                            <span>{run.display_name}</span>
                            <span class="bbh-run-link-meta">
                              {run.score_label} · {run.review_state}
                            </span>
                          </.link>
                        </li>
                      <% end %>
                    </ul>
                  </div>
                </article>
              <% else %>
                <.empty_state message="No active capsules yet." />
              <% end %>
            </.human_section>

            <.human_section id="bbh-wall-feed" title="Frontier ticker">
              <%= if @event_feed_items == [] do %>
                <.empty_state message="No frontier movement yet." />
              <% else %>
                <ol class="bbh-feed-list">
                  <%= for item <- @event_feed_items do %>
                    <li id={"bbh-feed-#{item.id}"} class="bbh-feed-item" data-motion="reveal">
                      <span class={["bbh-feed-dot", "is-#{item.kind}"]}></span>
                      <div>
                        <p class="bbh-feed-headline">{item.headline}</p>
                        <p class="bbh-feed-meta">
                          {item.occurred_at && Calendar.strftime(item.occurred_at, "%b %-d %H:%M UTC")}
                        </p>
                      </div>
                    </li>
                  <% end %>
                </ol>
              <% end %>
            </.human_section>
          </div>
        </section>

        <%= for board <- @official_boards do %>
          <.human_section id={official_board_section_id(board.key)} title={board.title}>
            <%= if board.entries == [] do %>
              <.empty_state message={board.empty_message} />
            <% else %>
              <div class="bbh-official-intro" data-motion="reveal">
                <p class="bbh-wall-kicker">{board.intro_kicker}</p>
                <p class="bbh-wall-note">{board.intro_note}</p>
              </div>

              <div class="bbh-official-strip">
                <%= for entry <- board.entries do %>
                  <article
                    id={official_board_entry_id(board.key, entry.node_id)}
                    class="bbh-official-card"
                    data-motion="reveal"
                  >
                    <p class="bbh-rank">#{entry.rank}</p>
                    <h2 class="bbh-name">{entry.display_name}</h2>
                    <div class="bbh-meter">
                      <span
                        class="bbh-meter-fill"
                        data-motion="score-bar"
                        style={"--bbh-score: #{(entry.score || 0.0) / 100.0}"}
                      >
                      </span>
                    </div>
                    <p class="bbh-official-meta">
                      {entry.score_label} · {entry.review_count} reviews
                    </p>
                    <.link navigate={~p"/bbh/runs/#{entry.node_id}"} class="bbh-run-link">
                      <span>Open run</span>
                      <span class="bbh-run-link-meta">validated</span>
                    </.link>
                  </article>
                <% end %>
              </div>
            <% end %>
          </.human_section>
        <% end %>
      </div>
    </main>
    """
  end

  defp assign_page(socket, page) do
    socket
    |> assign(:split, page.split)
    |> assign(:capsules, page.capsules)
    |> assign(:selected_capsule_id, page.selected_capsule_id)
    |> assign(:drilldown_capsule, page.drilldown_capsule)
    |> assign(:lane_sections, page.lane_sections)
    |> assign(:lane_counts, page.lane_counts)
    |> assign(:event_feed_items, page.event_feed_items)
    |> assign(:official_boards, page.official_boards)
    |> assign(:total_entries, page.total_entries)
    |> assign(:total_capsules, page.total_capsules)
    |> assign(:top_score, page.top_score)
    |> assign(:active_capsule_count, Enum.count(page.capsules, &(&1.active_agent_count > 0)))
    |> assign(:active_agent_count, Enum.reduce(page.capsules, 0, &(&1.active_agent_count + &2)))
    |> assign(:hot_capsule_count, Enum.count(page.capsules, & &1.is_hot))
  end

  defp outline_label(:new), do: "new"
  defp outline_label(:crowded), do: "crowded"
  defp outline_label(:saturated), do: "saturated"
  defp outline_label(:active), do: "active"
  defp outline_label(value) when is_binary(value), do: value
  defp outline_label(value), do: to_string(value)

  defp official_board_section_id(:benchmark), do: "bbh-official-strip"
  defp official_board_section_id(:challenge), do: "bbh-challenge-strip"
  defp official_board_section_id(key), do: "bbh-#{key}-strip"

  defp official_board_entry_id(:benchmark, run_id), do: "bbh-official-#{run_id}"
  defp official_board_entry_id(board_key, run_id), do: "bbh-#{board_key}-official-#{run_id}"

  defp wall_path(capsule_id) do
    ~p"/bbh?#{[focus: capsule_id]}"
  end
end
