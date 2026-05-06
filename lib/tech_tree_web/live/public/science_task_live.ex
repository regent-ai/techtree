defmodule TechTreeWeb.Public.ScienceTaskLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  alias TechTree.PublicSite
  alias TechTree.ScienceTasks
  alias TechTreeWeb.PublicSiteComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Science Task")
     |> assign(:ios_app_url, PublicSite.ios_app_url())
     |> assign(:task, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case ScienceTasks.get_public_task(id) do
      {:ok, task} ->
        task = ScienceTasks.encode_detail(task)

        {:noreply,
         socket
         |> assign(:task, task)
         |> assign(:page_title, task.title)}

      {:error, :science_task_invalid_id} ->
        {:noreply, push_navigate(socket, to: "/science-tasks")}

      {:error, :science_task_not_found} ->
        {:noreply, push_navigate(socket, to: "/science-tasks")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div
      id="science-task-detail-page"
      class="tt-public-shell"
      phx-hook="PublicSiteMotion"
      data-motion-scope="science-task-detail"
    >
      <PublicSiteComponents.public_topbar current={:science_tasks} ios_app_url={@ios_app_url} />

      <main :if={@task} class="tt-public-main">
        <section class="tt-public-page-hero">
          <div class="tt-public-hero-copy" data-public-reveal>
            <p class="tt-public-kicker"><PublicSiteComponents.sigil /> Science task</p>
            <h1>{@task.title}</h1>
            <p class="tt-public-hero-copy-text">
              {present(@task.summary, "This task does not have a short summary yet.")}
            </p>
          </div>

          <div class="tt-public-hero-actions tt-public-hero-actions-tight" data-public-reveal>
            <.link navigate={~p"/science-tasks"} class="tt-public-secondary-button">
              Back to board
            </.link>
            <.link
              :if={@task.node}
              navigate={~p"/tree/node/#{@task.node_id}"}
              class="tt-public-secondary-button"
            >
              Open tree node
            </.link>
          </div>
        </section>

        <section class="tt-public-tree-layout">
          <div class="tt-public-tree-main">
            <section class="tt-public-tree-canvas">
              <div class="tt-public-tree-grid">
                <article class="tt-public-tree-card" data-public-reveal>
                  <div class="tt-public-tree-card-head">
                    <span class="tt-public-seed-chip">Public record</span>
                    <span class="tt-public-room-chip">
                      {String.replace(@task.workflow_state, "_", " ")}
                    </span>
                  </div>
                  <ul class="tt-public-side-list-items">
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Domain</strong>
                          <p>{@task.science_domain}</p>
                        </div>
                      </div>
                    </li>
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Field</strong>
                          <p>{@task.science_field}</p>
                        </div>
                      </div>
                    </li>
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Task folder</strong>
                          <p
                            class="tt-public-copy-value"
                            data-copy-value={@task.export_target_path}
                            data-copy-label="Task folder"
                          >
                            {@task.export_target_path}
                          </p>
                        </div>
                        <button
                          type="button"
                          class="tt-public-copy-action"
                          data-copy-button
                          data-copy-value={@task.export_target_path}
                          data-copy-label="Task folder"
                        >
                          Copy
                        </button>
                      </div>
                    </li>
                  </ul>
                </article>

                <article class="tt-public-tree-card" data-public-reveal>
                  <div class="tt-public-tree-card-head">
                    <span class="tt-public-seed-chip">Review proof</span>
                    <span class="tt-public-room-chip">
                      {if @task.current_files_match_latest_evidence,
                        do: "files match proof",
                        else: "needs refresh"}
                    </span>
                  </div>
                  <ul class="tt-public-side-list-items">
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Task fingerprint</strong>
                          <p
                            class="tt-public-copy-value"
                            data-copy-value={@task.packet_hash}
                            data-copy-label="Task fingerprint"
                          >
                            {@task.packet_hash}
                          </p>
                        </div>
                        <button
                          type="button"
                          class="tt-public-copy-action"
                          data-copy-button
                          data-copy-value={@task.packet_hash}
                          data-copy-label="Task fingerprint"
                        >
                          Copy
                        </button>
                      </div>
                    </li>
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Proof fingerprint</strong>
                          <p
                            class="tt-public-copy-value"
                            data-copy-value={@task.evidence_packet_hash}
                            data-copy-label="Proof fingerprint"
                          >
                            {present(@task.evidence_packet_hash, "No proof fingerprint recorded yet.")}
                          </p>
                        </div>
                        <button
                          :if={@task.evidence_packet_hash}
                          type="button"
                          class="tt-public-copy-action"
                          data-copy-button
                          data-copy-value={@task.evidence_packet_hash}
                          data-copy-label="Proof fingerprint"
                        >
                          Copy
                        </button>
                      </div>
                    </li>
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Checklist</strong>
                          <p>
                            {checklist_pass_count(@task.checklist)} of {map_size(@task.checklist)} checks passed
                          </p>
                        </div>
                      </div>
                    </li>
                  </ul>
                </article>

                <article class="tt-public-tree-card" data-public-reveal>
                  <div class="tt-public-tree-card-head">
                    <span class="tt-public-seed-chip">Checklist</span>
                    <span class="tt-public-room-chip">
                      {checklist_pass_count(@task.checklist)}/{map_size(@task.checklist)} pass
                    </span>
                  </div>
                  <ul class="tt-public-side-list-items">
                    <%= for {key, entry} <- Enum.sort(@task.checklist) do %>
                      <li id={"science-task-checklist-#{key}"}>
                        <div class="tt-public-side-link">
                          <div>
                            <strong>{checklist_label(key)}</strong>
                            <p>{present(entry["note"], "No note recorded yet.")}</p>
                          </div>
                          <span>{String.upcase(entry["status"] || "unknown")}</span>
                        </div>
                      </li>
                    <% end %>
                  </ul>
                </article>

                <article class="tt-public-tree-card" data-public-reveal>
                  <div class="tt-public-tree-card-head">
                    <span class="tt-public-seed-chip">Run evidence</span>
                    <span class="tt-public-room-chip">
                      {if @task.current_files_match_latest_evidence,
                        do: "matches files",
                        else: "needs refresh"}
                    </span>
                  </div>
                  <ul class="tt-public-side-list-items">
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Baseline check</strong>
                          <p
                            class="tt-public-copy-value"
                            data-copy-value={evidence_value(@task.oracle_run, "command")}
                            data-copy-label="Baseline check"
                          >
                            {evidence_line(@task.oracle_run, "command")}
                          </p>
                        </div>
                        <button
                          :if={evidence_value(@task.oracle_run, "command")}
                          type="button"
                          class="tt-public-copy-action"
                          data-copy-button
                          data-copy-value={evidence_value(@task.oracle_run, "command")}
                          data-copy-label="Baseline check"
                        >
                          Copy
                        </button>
                      </div>
                    </li>
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Baseline result</strong>
                          <p>{evidence_line(@task.oracle_run, "summary")}</p>
                        </div>
                      </div>
                    </li>
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Frontier attempt</strong>
                          <p
                            class="tt-public-copy-value"
                            data-copy-value={evidence_value(@task.frontier_run, "command")}
                            data-copy-label="Frontier attempt"
                          >
                            {evidence_line(@task.frontier_run, "command")}
                          </p>
                        </div>
                        <button
                          :if={evidence_value(@task.frontier_run, "command")}
                          type="button"
                          class="tt-public-copy-action"
                          data-copy-button
                          data-copy-value={evidence_value(@task.frontier_run, "command")}
                          data-copy-label="Frontier attempt"
                        >
                          Copy
                        </button>
                      </div>
                    </li>
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Frontier result</strong>
                          <p>{evidence_line(@task.frontier_run, "summary")}</p>
                        </div>
                      </div>
                    </li>
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Failure analysis</strong>
                          <p>{@task.failure_analysis}</p>
                        </div>
                      </div>
                    </li>
                  </ul>
                </article>

                <article class="tt-public-tree-card" data-public-reveal>
                  <div class="tt-public-tree-card-head">
                    <span class="tt-public-seed-chip">Review loop</span>
                    <span class="tt-public-room-chip">
                      {@task.open_reviewer_concerns_count} open concerns
                    </span>
                  </div>
                  <ul class="tt-public-side-list-items">
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Review link</strong>
                          <p>{present(@task.harbor_pr_url, "No review link recorded yet.")}</p>
                        </div>
                      </div>
                    </li>
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Latest follow-up</strong>
                          <p>
                            {present(
                              @task.latest_review_follow_up_note,
                              "No follow-up note recorded yet."
                            )}
                          </p>
                        </div>
                      </div>
                    </li>
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Latest fix</strong>
                          <p>{present_datetime(@task.latest_fix_at)}</p>
                        </div>
                      </div>
                    </li>
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Latest rerun</strong>
                          <p>{present_datetime(@task.last_rerun_at)}</p>
                        </div>
                      </div>
                    </li>
                    <li>
                      <div class="tt-public-side-link">
                        <div>
                          <strong>Unanswered concern</strong>
                          <p>{if @task.any_concern_unanswered, do: "Yes", else: "No"}</p>
                        </div>
                      </div>
                    </li>
                  </ul>
                </article>
              </div>

              <section id="science-task-packet" class="tt-public-side-list" data-public-reveal>
                <div class="tt-public-side-list-head">
                  <h3>Task files</h3>
                  <p>Task packet files show what reviewers and future operators can inspect.</p>
                </div>

                <%= if @task.packet_files == %{} do %>
                  <div class="tt-public-empty-state">
                    No task files are visible for this task yet.
                    <.link navigate={~p"/science-tasks"} class="tt-public-inline-link">
                      Return to the task board
                    </.link>
                    to find another task with files attached.
                  </div>
                <% else %>
                  <div class="tt-public-room-feed">
                    <article
                      :for={{path, file} <- Enum.sort(@task.packet_files)}
                      id={"science-task-file-#{path}"}
                      class="tt-public-room-entry"
                    >
                      <div class="tt-public-room-entry-top">
                        <div class="tt-public-room-entry-copy">
                          <strong>{path}</strong>
                          <span class="tt-public-room-chip">{file["encoding"]}</span>
                        </div>
                        <button
                          type="button"
                          class="tt-public-copy-action"
                          data-copy-button
                          data-copy-value={file_body(file)}
                          data-copy-label={"Task file #{path}"}
                        >
                          Copy file
                        </button>
                      </div>
                      <pre>{file_body(file)}</pre>
                    </article>
                  </div>
                <% end %>
              </section>
            </section>
          </div>

          <aside class="tt-public-tree-side">
            <section id="science-task-detail-notes" class="tt-public-side-list" data-public-reveal>
              <div class="tt-public-side-list-head">
                <h3>Task notes</h3>
              </div>
              <ul class="tt-public-side-list-items">
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Expert time</strong>
                      <p>{@task.claimed_expert_time}</p>
                    </div>
                  </div>
                </li>
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Answer format</strong>
                      <p>{present_shape(@task.structured_output_shape)}</p>
                    </div>
                  </div>
                </li>
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Scoring threshold</strong>
                      <p>
                        {present(@task.threshold_rationale, "No scoring threshold note recorded.")}
                      </p>
                    </div>
                  </div>
                </li>
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Answer protection</strong>
                      <p>{@task.anti_cheat_notes}</p>
                    </div>
                  </div>
                </li>
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Repeatability notes</strong>
                      <p>{@task.reproducibility_notes}</p>
                    </div>
                  </div>
                </li>
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Version notes</strong>
                      <p>{@task.dependency_pinning_status}</p>
                    </div>
                  </div>
                </li>
                <li>
                  <div class="tt-public-side-link">
                    <div>
                      <strong>Hidden-answer check</strong>
                      <p>{@task.canary_status}</p>
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

  defp present(nil, fallback), do: fallback
  defp present("", fallback), do: fallback
  defp present(value, _fallback), do: value

  defp file_body(%{"encoding" => "utf8", "content" => content}), do: content

  defp file_body(%{"encoding" => "base64"}),
    do: "Binary file is available as an encoded attachment."

  defp file_body(_file), do: "File content unavailable."

  defp evidence_line(nil, _key), do: "Not recorded yet."
  defp evidence_line(run, key), do: present(run[key], "Not recorded yet.")

  defp evidence_value(nil, _key), do: nil
  defp evidence_value(run, key), do: present_copy_value(run[key])

  defp present_copy_value(value) when is_binary(value) and value != "", do: value
  defp present_copy_value(_value), do: nil

  defp present_shape(nil), do: "No answer format recorded."
  defp present_shape(shape), do: Jason.encode!(shape)

  defp present_datetime(nil), do: "Not recorded yet."

  defp present_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp checklist_pass_count(checklist) do
    Enum.count(checklist, fn {_key, entry} -> entry["status"] == "pass" end)
  end

  defp checklist_label(key) do
    ScienceTasks.checklist_specs()
    |> Enum.find_value(key, fn {entry_key, label} ->
      if entry_key == key, do: label, else: nil
    end)
  end
end
