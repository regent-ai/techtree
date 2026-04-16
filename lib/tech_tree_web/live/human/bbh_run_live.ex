defmodule TechTreeWeb.Human.BbhRunLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.HumanComponents

  alias TechTree.BBH.Presentation

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     case Presentation.run_page(id) do
       {:ok, page} ->
         socket
         |> assign(:not_found?, false)
         |> assign(:page_title, "BBH Run")
         |> assign(:run, page.run)
         |> assign(:validations, page.validations)
         |> assign(:score_cards, page.score_cards)
         |> assign(:execution_rows, page.execution_rows)
         |> assign(:artifact_rows, page.artifact_rows)

       :error ->
         socket
         |> assign(:not_found?, true)
         |> assign(:page_title, "BBH Run")
     end}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <main id="bbh-run-page" class="hu-page bbh-page" phx-hook="HumanMotion">
      <div class="hu-shell bbh-shell">
        <%= if @not_found? do %>
          <.human_header
            kicker="BBH Run"
            title="Run not found"
            subtitle="The requested run is unavailable."
          >
            <:actions>
              <.link navigate={~p"/bbh"} class="hu-primary-link">Back to leaderboard</.link>
            </:actions>
          </.human_header>
        <% else %>
          <.human_header
            kicker={@run.id}
            title={@run.genome.name}
            subtitle={@run.lane_subtitle}
          >
            <:actions>
              <.link navigate={~p"/bbh"} class="hu-ghost-link">Wall board</.link>
              <span class="bbh-chip">{@run.capsule_badge_kind}</span>
              <span class="bbh-chip">{@run.lane_label}</span>
              <span class="bbh-chip">{@run.operator_lane_tag}</span>
              <span class="bbh-chip">{@run.status_label}</span>
              <.link navigate={~p"/bbh"} class="hu-ghost-link">Benchmark ledger</.link>
              <span class="bbh-chip">{Float.round(@run.score_percent, 1)}%</span>
            </:actions>
          </.human_header>

          <.human_section id="bbh-run-score" title="Score">
            <div class="bbh-run-score">
              <div
                class="bbh-meter bbh-meter-large"
                style={"--bbh-score: #{@run.score_percent / 100.0}"}
              >
                <span class="bbh-meter-fill" data-motion="score-bar"></span>
              </div>
              <dl class="hu-stat-grid hu-stat-grid-wide">
                <%= for card <- @score_cards do %>
                  <.human_stat label={card.label} value={card.value} />
                <% end %>
              </dl>
            </div>
          </.human_section>

          <.human_section id="bbh-run-boundary" title="Benchmark ledger boundary">
            <div class="bbh-copy">
              <p>
                Capsule: <strong>{@run.capsule_title}</strong>
              </p>
              <p>
                {@run.ledger_boundary_note}
              </p>
            </div>
          </.human_section>

          <.human_section id="bbh-run-genome" title="Genome">
            <div class="bbh-copy">
              <p><strong>Model:</strong> {@run.genome.model}</p>
              <p><strong>Router:</strong> {@run.genome.router}</p>
              <p><strong>Fingerprint:</strong> {@run.genome.fingerprint || "n/a"}</p>
              <p><strong>Planner:</strong> {@run.genome.planner || "n/a"}</p>
              <p><strong>Critic:</strong> {@run.genome.critic || "n/a"}</p>
              <p><strong>Tool policy:</strong> {@run.genome.tool_policy || "n/a"}</p>
              <%= if @run.publication_review_id do %>
                <p><strong>Challenge review:</strong> {@run.publication_review_id}</p>
              <% end %>
              <%= if @run.published_at do %>
                <p><strong>Published:</strong> {@run.published_at}</p>
              <% end %>
            </div>
          </.human_section>

          <.human_section id="bbh-run-certificate" title="Certificate">
            <div class="bbh-copy">
              <p><strong>Status:</strong> {@run.certificate_status}</p>
              <%= if @run.certificate_review_id do %>
                <p><strong>Certificate review:</strong> {@run.certificate_review_id}</p>
              <% end %>
              <%= if @run.certificate_expires_at do %>
                <p><strong>Certificate expires:</strong> {@run.certificate_expires_at}</p>
              <% end %>
            </div>
          </.human_section>

          <.human_section id="bbh-run-execution" title="Execution">
            <div class="bbh-copy">
              <p>
                This section shows how the run was made. SkyDiscover appears here when the run used
                a search pass. Hypotest is the scorer behind the stored verdict and the replay
                result.
              </p>
            </div>
            <ul class="hu-list">
              <%= for row <- @execution_rows do %>
                <li id={"bbh-execution-#{row.id}"}>
                  <div class="hu-list-link">
                    <span>{row.label}</span>
                    <span class="hu-list-meta">{row.value}</span>
                  </div>
                </li>
              <% end %>
            </ul>
          </.human_section>

          <.human_section id="bbh-run-artifacts" title="Artifacts">
            <%= if @artifact_rows == [] do %>
              <.empty_state message="No public artifact metadata was attached to this run." />
            <% else %>
              <ul class="hu-list">
                <%= for row <- @artifact_rows do %>
                  <li id={"bbh-artifact-#{row.id}"}>
                    <div class="hu-list-link">
                      <span>{row.label}</span>
                      <span class="hu-list-meta">{row.value}</span>
                    </div>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </.human_section>

          <.human_section id="bbh-run-validations" title="Validations">
            <%= if @validations == [] do %>
              <.empty_state message="This run has not been replayed by a validator yet." />
            <% else %>
              <div class="bbh-validation-stack">
                <%= for validation <- @validations do %>
                  <article
                    id={"bbh-validation-#{validation.id}"}
                    class="bbh-validation"
                    data-motion="reveal"
                  >
                    <div class="bbh-validation-top">
                      <h3>{validation.validator_id}</h3>
                      <span class="bbh-badge">{validation.status_label}</span>
                    </div>
                    <p class="bbh-validation-copy">
                      {if validation.reproducible,
                        do: "Replay held cleanly and supports reviewed public status for this lane.",
                        else:
                          "Replay did not hold, so this run needs another clean replay before it can move forward."}
                    </p>
                    <dl class="bbh-validation-grid">
                      <div>
                        <dt>Kind</dt>
                        <dd>{stringify_enum(validation.validator_kind)}</dd>
                      </div>
                      <div>
                        <dt>Artifact match</dt>
                        <dd>{to_yes_no(validation.artifact_match)}</dd>
                      </div>
                      <div>
                        <dt>Score match</dt>
                        <dd>{to_yes_no(validation.score_match)}</dd>
                      </div>
                    </dl>
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

  defp to_yes_no(true), do: "yes"
  defp to_yes_no(_value), do: "no"

  defp stringify_enum(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_enum(value) when is_binary(value), do: value
  defp stringify_enum(value), do: to_string(value)
end
