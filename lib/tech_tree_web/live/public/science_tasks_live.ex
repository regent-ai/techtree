defmodule TechTreeWeb.Public.ScienceTasksLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.PublicSite
  alias TechTree.ScienceTasks
  alias TechTreeWeb.PublicSiteComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Science Tasks")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:tasks, [])
     |> assign(:stage_filter, nil)
     |> assign(:domain_filter, nil)
     |> assign(:field_filter, nil)
     |> assign(:domains, [])
     |> assign(:fields, [])
     |> assign(:counts, %{})}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tasks = ScienceTasks.list_public_tasks(params)

    {:noreply,
     socket
     |> assign(:tasks, tasks)
     |> assign(:stage_filter, blank_to_nil(params["stage"]))
     |> assign(:domain_filter, blank_to_nil(params["science_domain"]))
     |> assign(:field_filter, blank_to_nil(params["science_field"]))
     |> assign(:domains, tasks |> Enum.map(& &1.science_domain) |> Enum.uniq() |> Enum.sort())
     |> assign(:fields, tasks |> Enum.map(& &1.science_field) |> Enum.uniq() |> Enum.sort())
     |> assign(:counts, stage_counts(tasks))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div
      id="science-tasks-page"
      class="tt-public-shell"
      phx-hook="PublicSiteMotion"
      data-motion-scope="science-tasks"
    >
      <PublicSiteComponents.public_topbar current={:science_tasks} ios_app_url={@ios_app_url} />

      <main class="tt-public-main">
        <section class="tt-public-page-hero">
          <div class="tt-public-hero-copy" data-public-reveal>
            <p class="tt-public-kicker">Evals branch</p>
            <h1>Build science tasks that can clear Harbor review.</h1>
            <p class="tt-public-hero-copy-text">
              This branch is for turning real scientific workflows into benchmark tasks with the packet,
              evidence, anti-cheat notes, and review-loop follow-up needed for Terminal-Bench-Science.
            </p>
          </div>

          <div class="tt-public-hero-actions tt-public-hero-actions-tight" data-public-reveal>
            <.link navigate={~p"/tree/seed/Evals"} class="tt-public-secondary-button">
              Open Evals
            </.link>
            <.link navigate={~p"/learn/science-tasks"} class="tt-public-secondary-button">
              Read the branch guide
            </.link>
          </div>
        </section>

        <section class="tt-public-tree-layout">
          <div class="tt-public-tree-main">
            <section class="tt-public-tree-canvas">
              <div class="tt-public-side-list-head">
                <h3>Review board</h3>
                <p>
                  Track tasks by review stage, then open the full packet when you want the exact files,
                  checklist lines, and evidence that explain the current state.
                </p>
              </div>

              <div class="tt-public-chip-row" data-public-reveal>
                <.filter_chip
                  href={science_tasks_href(nil, @domain_filter, @field_filter)}
                  active={is_nil(@stage_filter)}
                >
                  All stages
                </.filter_chip>
                <.filter_chip
                  :for={stage <- ScienceTasks.stage_names()}
                  href={science_tasks_href(stage, @domain_filter, @field_filter)}
                  active={@stage_filter == stage}
                >
                  {stage_label(stage)} ({Map.get(@counts, stage, 0)})
                </.filter_chip>
              </div>

              <div :if={@domains != []} class="tt-public-chip-row" data-public-reveal>
                <.filter_chip
                  href={science_tasks_href(@stage_filter, nil, @field_filter)}
                  active={is_nil(@domain_filter)}
                >
                  All domains
                </.filter_chip>
                <.filter_chip
                  :for={domain <- @domains}
                  href={science_tasks_href(@stage_filter, domain, @field_filter)}
                  active={@domain_filter == domain}
                >
                  {domain}
                </.filter_chip>
              </div>

              <div :if={@fields != []} class="tt-public-chip-row" data-public-reveal>
                <.filter_chip
                  href={science_tasks_href(@stage_filter, @domain_filter, nil)}
                  active={is_nil(@field_filter)}
                >
                  All fields
                </.filter_chip>
                <.filter_chip
                  :for={field <- @fields}
                  href={science_tasks_href(@stage_filter, @domain_filter, field)}
                  active={@field_filter == field}
                >
                  {field}
                </.filter_chip>
              </div>

              <%= if @tasks == [] do %>
                <div class="tt-public-empty-state" data-public-reveal>
                  No science tasks match these filters yet.
                </div>
              <% else %>
                <div class="tt-public-tree-grid">
                  <%= for stage <- visible_stages(@stage_filter) do %>
                    <article
                      id={"science-task-stage-#{stage}"}
                      class="tt-public-tree-card"
                      data-public-reveal
                    >
                      <div class="tt-public-tree-card-head">
                        <span class="tt-public-seed-chip">{stage_label(stage)}</span>
                        <span class="tt-public-room-chip">{Map.get(@counts, stage, 0)} tasks</span>
                      </div>

                      <%= if tasks_for_stage(@tasks, stage) == [] do %>
                        <div class="tt-public-empty-state">
                          Nothing is in this stage right now.
                        </div>
                      <% else %>
                        <ul class="tt-public-tree-node-list">
                          <%= for task <- tasks_for_stage(@tasks, stage) do %>
                            <li id={"science-task-card-#{task.node_id}"}>
                              <.link
                                navigate={~p"/science-tasks/#{task.node_id}"}
                                class="tt-public-tree-node-link"
                              >
                                <div>
                                  <strong>{task.node.title}</strong>
                                  <p>{task.science_domain} · {task.science_field}</p>
                                </div>
                                <div class="tt-public-chip-row">
                                  <span class="tt-public-room-chip">{task.task_slug}</span>
                                  <span class="tt-public-room-chip">
                                    {if current_files_match_latest_evidence?(task),
                                      do: "evidence current",
                                      else: "rerun needed"}
                                  </span>
                                </div>
                              </.link>
                            </li>
                          <% end %>
                        </ul>
                      <% end %>
                    </article>
                  <% end %>
                </div>
              <% end %>
            </section>
          </div>

          <aside class="tt-public-tree-side">
            <section id="science-task-branch-notes" class="tt-public-side-list" data-public-reveal>
              <div class="tt-public-side-list-head">
                <h3>What counts as done</h3>
              </div>
              <ul class="tt-public-side-list-items">
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Real task packet</strong>
                      <p>
                        The stored packet includes the actual Harbor task files, not a summary layer.
                      </p>
                    </div>
                  </div>
                </li>
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Blocking checklist</strong>
                      <p>A single fail or unknown line keeps the task out of the ready stages.</p>
                    </div>
                  </div>
                </li>
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Evidence matches files</strong>
                      <p>Oracle and frontier commands have to match the current packet hash.</p>
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

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp tasks_for_stage(tasks, stage) do
    Enum.filter(tasks, &(Atom.to_string(&1.workflow_state) == stage))
  end

  defp stage_counts(tasks) do
    Enum.reduce(tasks, %{}, fn task, acc ->
      Map.update(acc, Atom.to_string(task.workflow_state), 1, &(&1 + 1))
    end)
  end

  defp visible_stages(nil), do: ScienceTasks.stage_names()
  defp visible_stages(stage), do: [stage]

  defp current_files_match_latest_evidence?(task) do
    is_binary(task.evidence_packet_hash) and task.evidence_packet_hash == task.packet_hash
  end

  defp stage_label("authoring"), do: "Authoring"
  defp stage_label("checklist_fix"), do: "Checklist fix"
  defp stage_label("evidence_ready"), do: "Evidence ready"
  defp stage_label("submitted"), do: "Submitted"
  defp stage_label("review_fix"), do: "Review fix"
  defp stage_label("merge_ready"), do: "Merge ready"
  defp stage_label(stage), do: stage

  defp science_tasks_href(stage, science_domain, science_field) do
    query =
      []
      |> maybe_put_query("stage", stage)
      |> maybe_put_query("science_domain", science_domain)
      |> maybe_put_query("science_field", science_field)

    case query do
      [] -> "/science-tasks"
      entries -> "/science-tasks?" <> URI.encode_query(entries)
    end
  end

  defp maybe_put_query(query, _key, nil), do: query
  defp maybe_put_query(query, key, value), do: [{key, value} | query]
end
