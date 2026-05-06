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
     |> assign(:loop_steps, science_task_loop_steps())
     |> assign(:science_tasks_page, empty_page())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case ScienceTasks.public_index_page(params) do
      {:ok, page} ->
        {:noreply,
         socket
         |> assign(:science_tasks_page, page)}

      {:error, :science_task_invalid_stage, %{redirect_href: redirect_href}} ->
        {:noreply, push_navigate(socket, to: redirect_href)}
    end
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
            <p class="tt-public-kicker"><PublicSiteComponents.sigil /> Evals branch</p>
            <h1>Build science tasks that can survive review.</h1>
            <p class="tt-public-hero-copy-text">
              This branch gathers real scientific workflows into Harbor-ready tasks with files,
              checks, run evidence, and reviewer follow-up.
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

        <section class="tt-public-section tt-public-section-tight">
          <PublicSiteComponents.research_loop
            loop_id="science-task-core-loop"
            steps={@loop_steps}
            title="A task moves only when the evidence moves"
            copy="The board is organized around the same review sequence every task follows."
          />
        </section>

        <section class="tt-public-tree-layout">
          <div class="tt-public-tree-main">
            <section class="tt-public-tree-canvas">
              <div class="tt-public-side-list-head">
                <h3>Review board</h3>
                <p>
                  Track tasks by review stage, then open a task when you want the files,
                  checklist notes, run evidence, and current reviewer state.
                </p>
              </div>

              <div class="tt-public-chip-row" data-public-reveal>
                <.filter_chip
                  href={
                    ScienceTasks.public_index_href(
                      nil,
                      @science_tasks_page.domain_filter,
                      @science_tasks_page.field_filter
                    )
                  }
                  active={is_nil(@science_tasks_page.stage_filter)}
                >
                  All stages
                </.filter_chip>
                <.filter_chip
                  :for={stage <- @science_tasks_page.stage_names}
                  href={
                    ScienceTasks.public_index_href(
                      stage,
                      @science_tasks_page.domain_filter,
                      @science_tasks_page.field_filter
                    )
                  }
                  active={@science_tasks_page.stage_filter == stage}
                >
                  {ScienceTasks.stage_label(stage)} ({Map.get(@science_tasks_page.counts, stage, 0)})
                </.filter_chip>
              </div>

              <div
                :if={@science_tasks_page.domains != []}
                class="tt-public-chip-row"
                data-public-reveal
              >
                <.filter_chip
                  href={
                    ScienceTasks.public_index_href(
                      @science_tasks_page.stage_filter,
                      nil,
                      @science_tasks_page.field_filter
                    )
                  }
                  active={is_nil(@science_tasks_page.domain_filter)}
                >
                  All domains
                </.filter_chip>
                <.filter_chip
                  :for={domain <- @science_tasks_page.domains}
                  href={
                    ScienceTasks.public_index_href(
                      @science_tasks_page.stage_filter,
                      domain,
                      @science_tasks_page.field_filter
                    )
                  }
                  active={@science_tasks_page.domain_filter == domain}
                >
                  {domain}
                </.filter_chip>
              </div>

              <div
                :if={@science_tasks_page.fields != []}
                class="tt-public-chip-row"
                data-public-reveal
              >
                <.filter_chip
                  href={
                    ScienceTasks.public_index_href(
                      @science_tasks_page.stage_filter,
                      @science_tasks_page.domain_filter,
                      nil
                    )
                  }
                  active={is_nil(@science_tasks_page.field_filter)}
                >
                  All fields
                </.filter_chip>
                <.filter_chip
                  :for={field <- @science_tasks_page.fields}
                  href={
                    ScienceTasks.public_index_href(
                      @science_tasks_page.stage_filter,
                      @science_tasks_page.domain_filter,
                      field
                    )
                  }
                  active={@science_tasks_page.field_filter == field}
                >
                  {field}
                </.filter_chip>
              </div>

              <%= if @science_tasks_page.tasks == [] do %>
                <div class="tt-public-empty-state" data-public-reveal>
                  No science tasks match these filters yet.
                </div>
              <% else %>
                <div class="tt-public-tree-grid">
                  <%= for stage <- @science_tasks_page.visible_stages do %>
                    <article
                      id={"science-task-stage-#{stage}"}
                      class="tt-public-tree-card"
                      data-public-reveal
                    >
                      <div class="tt-public-tree-card-head">
                        <span class="tt-public-seed-chip">{ScienceTasks.stage_label(stage)}</span>
                        <span class="tt-public-room-chip">
                          {Map.get(@science_tasks_page.counts, stage, 0)} tasks
                        </span>
                      </div>

                      <%= if Map.get(@science_tasks_page.tasks_by_stage, stage, []) == [] do %>
                        <div class="tt-public-empty-state">
                          Nothing is in this stage right now.
                        </div>
                      <% else %>
                        <ul class="tt-public-tree-node-list">
                          <%= for task <- Map.get(@science_tasks_page.tasks_by_stage, stage, []) do %>
                            <li id={"science-task-card-#{task.node_id}"}>
                              <.link
                                navigate={~p"/science-tasks/#{task.node_id}"}
                                class="tt-public-tree-node-link"
                              >
                                <div>
                                  <strong>{task.title}</strong>
                                  <p>{task.science_domain} · {task.science_field}</p>
                                </div>
                                <div class="tt-public-chip-row">
                                  <span class="tt-public-room-chip">{task.task_slug}</span>
                                  <span class="tt-public-room-chip">{task.evidence_label}</span>
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
                      <strong>Real task files</strong>
                      <p>
                        Each task includes the files and checks reviewers inspect, not just a summary.
                      </p>
                    </div>
                  </div>
                </li>
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Blocking checklist</strong>
                      <p>The Harbor checklist stays visible until each required check passes.</p>
                    </div>
                  </div>
                </li>
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Proof matches the task</strong>
                      <p>The evidence, notes, and reviewer follow-up stay attached to the task.</p>
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

  defp empty_page do
    %{
      tasks: [],
      tasks_by_stage: %{},
      stage_filter: nil,
      domain_filter: nil,
      field_filter: nil,
      domains: [],
      fields: [],
      counts: %{},
      stage_names: ScienceTasks.stage_names(),
      visible_stages: ScienceTasks.stage_names()
    }
  end

  defp science_task_loop_steps do
    [
      %{id: "packet", title: "Packet", copy: "Write the task files and expected checks."},
      %{id: "review", title: "Review", copy: "Run Hermes with the Harbor checklist."},
      %{id: "evidence", title: "Evidence", copy: "Record baseline and frontier runs."},
      %{id: "follow-up", title: "Follow up", copy: "Answer reviewer concerns and rerun checks."},
      %{id: "export", title: "Export", copy: "Prepare the submission folder."}
    ]
  end
end
