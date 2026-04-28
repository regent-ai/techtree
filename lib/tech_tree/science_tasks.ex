defmodule TechTree.ScienceTasks do
  @moduledoc false

  import Ecto.Query

  alias Decimal, as: D
  alias TechTree.Activity
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Repo
  alias TechTree.ScienceTasks.ScienceTask
  alias TechTreeWeb.PublicEncoding

  @science_branch_slug "science-tasks"
  @science_seed "Evals"
  @science_task_slug_regex ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
  @packet_required_files [
    "instruction.md",
    "task.toml"
  ]

  @checklist_specs [
    {"instruction_and_tests_match", "instruction and tests match exactly"},
    {"tests_do_not_check_hidden_behavior", "tests do not check hidden behavior"},
    {"structured_output_described_exactly", "structured output is described exactly when needed"},
    {"difficulty_comes_from_work", "difficulty comes from the work, not vague wording"},
    {"expert_time_is_believable", "expert time claim is believable"},
    {"thresholds_are_defended", "thresholds are defended"},
    {"hidden_answers_not_easy_to_fetch", "hidden answers are not easy to read or fetch"},
    {"dependencies_pinned_when_needed", "dependencies are pinned when they matter"},
    {"environment_reproducible_for_reruns", "the environment is reproducible enough for reruns"},
    {"schema_and_policy_details_correct", "schema and policy details are correct"},
    {"canary_requirements_met", "canary requirements are met"},
    {"unrelated_file_drift_absent", "unrelated file drift is absent"},
    {"oracle_evidence_exists", "oracle evidence exists with exact command"},
    {"frontier_evidence_exists", "frontier evidence exists with exact command"},
    {"failure_analysis_is_honest",
     "failure analysis explains agent limits without hiding task flaws"},
    {"open_reviewer_concerns_answered", "every open Harbor reviewer concern has a direct answer"}
  ]

  @checklist_keys Enum.map(@checklist_specs, &elem(&1, 0))

  @spec checklist_specs() :: [{String.t(), String.t()}]
  def checklist_specs, do: @checklist_specs

  @spec ensure_public_branch_root!() :: Node.t()
  def ensure_public_branch_root!, do: ensure_branch_root!()

  @spec list_public_tasks(map()) :: [ScienceTask.t()]
  def list_public_tasks(params \\ %{}) when is_map(params) do
    limit = parse_limit(params)

    query =
      ScienceTask
      |> join(:inner, [task], node in Node, on: node.id == task.node_id)
      |> join(:inner, [task, node], agent in AgentIdentity, on: agent.id == node.creator_agent_id)
      |> where([task, node, agent], node.status == :anchored and agent.status == "active")
      |> maybe_filter_stage(params["stage"])
      |> maybe_filter_string(:science_domain, params["science_domain"])
      |> maybe_filter_string(:science_field, params["science_field"])
      |> order_by([task, node], asc: task.workflow_state, desc: node.inserted_at, desc: node.id)
      |> limit(^limit)

    Repo.all(query)
    |> Repo.preload(node: :creator_agent)
  end

  @spec public_index_page(map()) ::
          {:ok, map()} | {:error, :science_task_invalid_stage, %{redirect_href: String.t()}}
  def public_index_page(params \\ %{}) when is_map(params) do
    stage_filter = blank_to_nil(params["stage"])
    domain_filter = blank_to_nil(params["science_domain"])
    field_filter = blank_to_nil(params["science_field"])

    case normalize_stage(stage_filter) do
      {:ok, normalized_stage_filter} ->
        tasks =
          params
          |> Map.put("stage", normalized_stage_filter)
          |> Map.put("science_domain", domain_filter)
          |> Map.put("science_field", field_filter)
          |> list_public_tasks()

        cards = Enum.map(tasks, &public_index_task_card/1)
        stage_names = stage_names()

        {:ok,
         %{
           tasks: cards,
           tasks_by_stage: Enum.group_by(cards, & &1.stage),
           stage_filter: normalized_stage_filter,
           domain_filter: domain_filter,
           field_filter: field_filter,
           domains: cards |> Enum.map(& &1.science_domain) |> Enum.uniq() |> Enum.sort(),
           fields: cards |> Enum.map(& &1.science_field) |> Enum.uniq() |> Enum.sort(),
           counts: stage_counts(cards),
           stage_names: stage_names,
           visible_stages: visible_stages(normalized_stage_filter, stage_names)
         }}

      {:error, :science_task_invalid_stage} ->
        {:error, :science_task_invalid_stage,
         %{
           redirect_href: public_index_href(nil, domain_filter, field_filter)
         }}
    end
  end

  @spec public_index_href(String.t() | nil, String.t() | nil, String.t() | nil) :: String.t()
  def public_index_href(stage, science_domain, science_field) do
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

  @spec get_public_task(integer() | String.t()) ::
          {:ok, ScienceTask.t()} | {:error, :science_task_invalid_id | :science_task_not_found}
  def get_public_task(node_id) do
    with {:ok, normalized_id} <- normalize_task_id(node_id) do
      ScienceTask
      |> join(:inner, [task], node in Node, on: node.id == task.node_id)
      |> join(:inner, [task, node], agent in AgentIdentity, on: agent.id == node.creator_agent_id)
      |> where(
        [task, node, agent],
        task.node_id == ^normalized_id and node.status == :anchored and agent.status == "active"
      )
      |> preload([task, node], node: {node, :creator_agent})
      |> Repo.one()
      |> case do
        %ScienceTask{} = task -> {:ok, task}
        nil -> {:error, :science_task_not_found}
      end
    end
  end

  @spec create_task(AgentIdentity.t(), map()) :: {:ok, ScienceTask.t()} | {:error, term()}
  def create_task(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    with {:ok, normalized} <- normalize_base_input(attrs),
         {:ok, branch_root} <- {:ok, ensure_branch_root!()} do
      Repo.transaction(fn ->
        with {:ok, node} <- insert_task_node(agent, branch_root, normalized),
             task_attrs <-
               normalized
               |> build_task_attrs()
               |> Map.put(:node_id, node.id)
               |> Map.put(:checklist, default_checklist())
               |> put_stage(),
             {:ok, task} <- %ScienceTask{} |> ScienceTask.changeset(task_attrs) |> Repo.insert() do
          Nodes.refresh_parent_child_metrics!(branch_root.id)
          Nodes.refresh_activity_score!(node.id)

          Activity.log!(
            "science_task.created",
            :agent,
            agent.id,
            node.id,
            %{"node_id" => node.id, "title" => node.title, "seed" => node.seed}
          )

          Repo.preload(task, node: :creator_agent)
        else
          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)
    end
  end

  @spec update_checklist(AgentIdentity.t(), integer() | String.t(), map()) ::
          {:ok, ScienceTask.t()} | {:error, term()}
  def update_checklist(%AgentIdentity{} = agent, node_id, attrs) when is_map(attrs) do
    with {:ok, task} <- fetch_agent_task(agent, node_id),
         {:ok, normalized} <- normalize_base_input(attrs),
         {:ok, checklist} <- normalize_checklist(attrs["checklist"] || attrs[:checklist]) do
      update_task(task, normalized, %{
        checklist: checklist,
        event_type: "science_task.checklist_updated",
        actor_id: agent.id
      })
    end
  end

  @spec update_evidence(AgentIdentity.t(), integer() | String.t(), map()) ::
          {:ok, ScienceTask.t()} | {:error, term()}
  def update_evidence(%AgentIdentity{} = agent, node_id, attrs) when is_map(attrs) do
    with {:ok, task} <- fetch_agent_task(agent, node_id),
         {:ok, normalized} <- normalize_base_input(attrs),
         {:ok, oracle_run} <- normalize_run(attrs["oracle_run"] || attrs[:oracle_run]),
         {:ok, frontier_run} <- normalize_run(attrs["frontier_run"] || attrs[:frontier_run]) do
      update_task(task, normalized, %{
        oracle_run: oracle_run,
        frontier_run: frontier_run,
        evidence_packet_hash: normalized.packet_hash,
        event_type: "science_task.evidence_updated",
        actor_id: agent.id
      })
    end
  end

  @spec submit_task(AgentIdentity.t(), integer() | String.t(), map()) ::
          {:ok, ScienceTask.t()} | {:error, term()}
  def submit_task(%AgentIdentity{} = agent, node_id, attrs) when is_map(attrs) do
    with {:ok, task} <- fetch_agent_task(agent, node_id),
         {:ok, normalized} <- normalize_base_input(attrs),
         {:ok, harbor_pr_url} <-
           normalize_required_text(
             attrs["harbor_pr_url"] || attrs[:harbor_pr_url],
             :harbor_pr_url
           ) do
      update_task(task, normalized, %{
        harbor_pr_url: harbor_pr_url,
        latest_review_follow_up_note:
          normalize_optional_text(
            attrs["latest_review_follow_up_note"] || attrs[:latest_review_follow_up_note]
          ),
        event_type: "science_task.submitted",
        actor_id: agent.id
      })
    end
  end

  @spec update_review_loop(AgentIdentity.t(), integer() | String.t(), map()) ::
          {:ok, ScienceTask.t()} | {:error, term()}
  def update_review_loop(%AgentIdentity{} = agent, node_id, attrs) when is_map(attrs) do
    with {:ok, task} <- fetch_agent_task(agent, node_id),
         {:ok, normalized} <- normalize_base_input(attrs),
         {:ok, harbor_pr_url} <-
           normalize_required_text(param(attrs, "harbor_pr_url"), :harbor_pr_url),
         {:ok, concern_count} <-
           normalize_non_negative_integer(
             param(attrs, "open_reviewer_concerns_count"),
             :open_reviewer_concerns_count
           ),
         {:ok, any_concern_unanswered} <-
           normalize_boolean(param(attrs, "any_concern_unanswered"), :any_concern_unanswered),
         {:ok, latest_rerun_after_latest_fix} <-
           normalize_boolean(
             param(attrs, "latest_rerun_after_latest_fix"),
             :latest_rerun_after_latest_fix
           ),
         {:ok, latest_fix_at} <-
           normalize_optional_datetime(param(attrs, "latest_fix_at"), :latest_fix_at),
         {:ok, last_rerun_at} <-
           normalize_optional_datetime(param(attrs, "last_rerun_at"), :last_rerun_at) do
      update_task(task, normalized, %{
        harbor_pr_url: harbor_pr_url,
        latest_review_follow_up_note:
          normalize_optional_text(param(attrs, "latest_review_follow_up_note")),
        open_reviewer_concerns_count: concern_count,
        any_concern_unanswered: any_concern_unanswered,
        latest_rerun_after_latest_fix: latest_rerun_after_latest_fix,
        latest_fix_at: latest_fix_at,
        last_rerun_at: last_rerun_at,
        review_round_count: task.review_round_count + 1,
        event_type: "science_task.review_updated",
        actor_id: agent.id
      })
    end
  end

  @spec encode_summary(ScienceTask.t()) :: map()
  def encode_summary(%ScienceTask{} = task) do
    node = task.node

    %{
      node_id: task.node_id,
      title: node && node.title,
      summary: node && node.summary,
      science_domain: task.science_domain,
      science_field: task.science_field,
      task_slug: task.task_slug,
      workflow_state: Atom.to_string(task.workflow_state),
      export_target_path: export_target_path(task),
      harbor_pr_url: task.harbor_pr_url,
      review_round_count: task.review_round_count,
      open_reviewer_concerns_count: task.open_reviewer_concerns_count,
      current_files_match_latest_evidence: current_files_match_latest_evidence?(task),
      latest_rerun_after_latest_fix: task.latest_rerun_after_latest_fix,
      inserted_at: task.inserted_at,
      updated_at: task.updated_at
    }
  end

  @spec encode_detail(ScienceTask.t()) :: map()
  def encode_detail(%ScienceTask{} = task) do
    encode_summary(task)
    |> Map.merge(%{
      node: if(task.node, do: PublicEncoding.encode_node(task.node), else: nil),
      structured_output_shape: task.structured_output_shape,
      claimed_expert_time: task.claimed_expert_time,
      threshold_rationale: task.threshold_rationale,
      anti_cheat_notes: task.anti_cheat_notes,
      reproducibility_notes: task.reproducibility_notes,
      dependency_pinning_status: task.dependency_pinning_status,
      canary_status: task.canary_status,
      destination_name: task.destination_name,
      packet_hash: task.packet_hash,
      evidence_packet_hash: task.evidence_packet_hash,
      packet_files: task.packet_files || %{},
      checklist: task.checklist || %{},
      oracle_run: task.oracle_run,
      frontier_run: task.frontier_run,
      failure_analysis: task.failure_analysis,
      latest_review_follow_up_note: task.latest_review_follow_up_note,
      last_rerun_at: task.last_rerun_at,
      latest_fix_at: task.latest_fix_at,
      any_concern_unanswered: task.any_concern_unanswered
    })
  end

  @spec mutation_payload(ScienceTask.t()) :: map()
  def mutation_payload(%ScienceTask{} = task) do
    %{
      node_id: task.node_id,
      workflow_state: Atom.to_string(task.workflow_state),
      packet_hash: task.packet_hash,
      export_target_path: export_target_path(task)
    }
  end

  @spec export_target_path(ScienceTask.t()) :: String.t()
  def export_target_path(%ScienceTask{} = task) do
    "tasks/#{task.science_domain}/#{task.science_field}/#{task.task_slug}"
  end

  @spec stage_names() :: [String.t()]
  def stage_names do
    ScienceTask.workflow_states()
    |> Enum.map(&Atom.to_string/1)
  end

  @spec stage_label(String.t()) :: String.t()
  def stage_label("authoring"), do: "Authoring"
  def stage_label("checklist_fix"), do: "Checklist fix"
  def stage_label("evidence_ready"), do: "Evidence ready"
  def stage_label("submitted"), do: "Submitted"
  def stage_label("review_fix"), do: "Review fix"
  def stage_label("merge_ready"), do: "Merge ready"
  def stage_label(stage), do: stage

  @spec normalize_stage(String.t() | nil) ::
          {:ok, String.t() | nil} | {:error, :science_task_invalid_stage}
  def normalize_stage(nil), do: {:ok, nil}

  def normalize_stage(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        {:ok, nil}

      trimmed in stage_names() ->
        {:ok, trimmed}

      true ->
        {:error, :science_task_invalid_stage}
    end
  end

  def normalize_stage(_value), do: {:error, :science_task_invalid_stage}

  @spec checklist_keys() :: [String.t()]
  def checklist_keys, do: @checklist_keys

  defp update_task(task, normalized, extra_attrs) do
    attrs =
      task
      |> Map.from_struct()
      |> Map.take([
        :harbor_pr_url,
        :review_round_count,
        :open_reviewer_concerns_count,
        :latest_rerun_after_latest_fix,
        :latest_review_follow_up_note,
        :last_rerun_at,
        :latest_fix_at,
        :any_concern_unanswered,
        :evidence_packet_hash,
        :checklist,
        :oracle_run,
        :frontier_run
      ])
      |> Map.merge(build_task_attrs(normalized))
      |> Map.merge(extra_attrs)
      |> Map.drop([:event_type, :actor_id])
      |> put_stage()

    Repo.transaction(fn ->
      case task |> ScienceTask.changeset(attrs) |> Repo.update() do
        {:ok, updated} ->
          if task.node do
            task.node
            |> Ecto.Changeset.change(%{
              title: normalized.title,
              summary: normalized.summary,
              slug: normalized.task_slug
            })
            |> Repo.update!()
          end

          Activity.log!(
            extra_attrs.event_type,
            :agent,
            extra_attrs.actor_id,
            updated.node_id,
            %{
              "node_id" => updated.node_id,
              "workflow_state" => Atom.to_string(updated.workflow_state),
              "title" => task.node && task.node.title
            }
          )

          Repo.preload(updated, node: :creator_agent)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp fetch_agent_task(%AgentIdentity{id: agent_id}, node_id) do
    with {:ok, normalized_id} <- normalize_task_id(node_id) do
      ScienceTask
      |> join(:inner, [task], node in Node, on: node.id == task.node_id)
      |> where(
        [task, node],
        task.node_id == ^normalized_id and node.creator_agent_id == ^agent_id
      )
      |> preload([task, node], node: {node, :creator_agent})
      |> Repo.one()
      |> case do
        %ScienceTask{} = task -> {:ok, task}
        nil -> {:error, :science_task_not_found}
      end
    end
  end

  defp normalize_base_input(attrs) do
    with {:ok, title} <- normalize_required_text(attrs["title"] || attrs[:title], :title),
         {:ok, science_domain} <-
           normalize_slug(attrs["science_domain"] || attrs[:science_domain], :science_domain),
         {:ok, science_field} <-
           normalize_slug(attrs["science_field"] || attrs[:science_field], :science_field),
         {:ok, task_slug} <- normalize_slug(attrs["task_slug"] || attrs[:task_slug], :task_slug),
         {:ok, claimed_expert_time} <-
           normalize_required_text(
             attrs["claimed_expert_time"] || attrs[:claimed_expert_time],
             :claimed_expert_time
           ),
         {:ok, anti_cheat_notes} <-
           normalize_required_text(
             attrs["anti_cheat_notes"] || attrs[:anti_cheat_notes],
             :anti_cheat_notes
           ),
         {:ok, reproducibility_notes} <-
           normalize_required_text(
             attrs["reproducibility_notes"] || attrs[:reproducibility_notes],
             :reproducibility_notes
           ),
         {:ok, dependency_pinning_status} <-
           normalize_required_text(
             attrs["dependency_pinning_status"] || attrs[:dependency_pinning_status],
             :dependency_pinning_status
           ),
         {:ok, canary_status} <-
           normalize_required_text(
             attrs["canary_status"] || attrs[:canary_status],
             :canary_status
           ),
         {:ok, failure_analysis} <-
           normalize_required_text(
             attrs["failure_analysis"] || attrs[:failure_analysis],
             :failure_analysis
           ),
         {:ok, packet_files} <-
           normalize_packet_files(attrs["packet_files"] || attrs[:packet_files]),
         {:ok, structured_output_shape} <-
           normalize_optional_map(
             attrs["structured_output_shape"] || attrs[:structured_output_shape],
             :structured_output_shape
           ) do
      {:ok,
       %{
         title: title,
         summary: normalize_optional_text(attrs["summary"] || attrs[:summary]),
         science_domain: science_domain,
         science_field: science_field,
         task_slug: task_slug,
         structured_output_shape: structured_output_shape,
         claimed_expert_time: claimed_expert_time,
         threshold_rationale:
           normalize_optional_text(attrs["threshold_rationale"] || attrs[:threshold_rationale]),
         anti_cheat_notes: anti_cheat_notes,
         reproducibility_notes: reproducibility_notes,
         dependency_pinning_status: dependency_pinning_status,
         canary_status: canary_status,
         failure_analysis: failure_analysis,
         destination_name:
           normalize_optional_text(attrs["destination_name"] || attrs[:destination_name]) ||
             "terminal-bench-science",
         packet_files: packet_files,
         packet_hash: packet_hash(packet_files)
       }}
    end
  end

  defp normalize_checklist(value) when is_map(value) do
    normalized =
      Enum.reduce(@checklist_keys, %{}, fn key, acc ->
        entry = Map.get(value, key)

        normalized_entry =
          case entry do
            %{"status" => status} ->
              %{
                status: normalize_checklist_status(status),
                note: normalize_optional_text(entry["note"])
              }

            %{status: status} ->
              %{
                status: normalize_checklist_status(status),
                note: normalize_optional_text(entry[:note])
              }

            nil ->
              %{status: "unknown", note: nil}

            _ ->
              %{status: :invalid}
          end

        Map.put(acc, key, normalized_entry)
      end)

    if Enum.any?(normalized, fn {_key, entry} -> entry.status == :invalid end) do
      {:error, :science_task_checklist_invalid}
    else
      {:ok, normalized}
    end
  end

  defp normalize_checklist(_value), do: {:error, :science_task_checklist_invalid}

  defp normalize_run(value) when is_map(value) do
    with {:ok, command} <- normalize_required_text(value["command"] || value[:command], :command),
         {:ok, summary} <- normalize_required_text(value["summary"] || value[:summary], :summary),
         {:ok, key_lines} <-
           normalize_string_list(value["key_lines"] || value[:key_lines], :key_lines) do
      {:ok,
       %{
         "command" => command,
         "summary" => summary,
         "key_lines" => key_lines
       }}
    end
  end

  defp normalize_run(_value), do: {:error, :science_task_run_invalid}

  defp normalize_packet_files(value) when is_map(value) and map_size(value) > 0 do
    normalized =
      Enum.reduce_while(value, %{}, fn {path, file}, acc ->
        with {:ok, normalized_path} <- normalize_packet_path(path),
             {:ok, normalized_file} <- normalize_packet_file(file) do
          {:cont, Map.put(acc, normalized_path, normalized_file)}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case normalized do
      {:error, reason} ->
        {:error, reason}

      packet_files ->
        case validate_required_packet_files(packet_files) do
          :ok -> {:ok, packet_files}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp normalize_packet_files(_value), do: {:error, :science_task_packet_files_invalid}

  defp normalize_packet_path(path) when is_binary(path) do
    trimmed = String.trim(path)

    cond do
      trimmed == "" -> {:error, :science_task_packet_path_invalid}
      String.starts_with?(trimmed, "/") -> {:error, :science_task_packet_path_invalid}
      String.contains?(trimmed, "..") -> {:error, :science_task_packet_path_invalid}
      true -> {:ok, trimmed}
    end
  end

  defp normalize_packet_path(_path), do: {:error, :science_task_packet_path_invalid}

  defp normalize_packet_file(%{"encoding" => encoding, "content" => content}) do
    normalize_packet_file(%{encoding: encoding, content: content})
  end

  defp normalize_packet_file(%{encoding: encoding, content: content})
       when encoding in ["utf8", "base64"] and is_binary(content) and byte_size(content) > 0 do
    {:ok, %{"encoding" => encoding, "content" => content}}
  end

  defp normalize_packet_file(_value), do: {:error, :science_task_packet_file_invalid}

  defp validate_required_packet_files(packet_files) do
    has_tests = Enum.any?(Map.keys(packet_files), &String.starts_with?(&1, "tests/"))
    has_scripts = Enum.any?(Map.keys(packet_files), &String.starts_with?(&1, "scripts/"))

    has_notes =
      Enum.any?(
        Map.keys(packet_files),
        &(String.starts_with?(&1, "notes/") or &1 == "task-notes.md")
      )

    has_solution =
      Enum.any?(
        Map.keys(packet_files),
        &(&1 in ["solution.md", "solution-notes.md", "reference-solution.md"])
      )

    cond do
      Enum.any?(@packet_required_files, &(not Map.has_key?(packet_files, &1))) ->
        {:error, :science_task_packet_missing_required_file}

      not has_tests ->
        {:error, :science_task_packet_missing_tests}

      not has_scripts ->
        {:error, :science_task_packet_missing_scripts}

      not has_notes ->
        {:error, :science_task_packet_missing_notes}

      not has_solution ->
        {:error, :science_task_packet_missing_solution_notes}

      true ->
        :ok
    end
  end

  defp normalize_required_text(value, _field) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :required}
      trimmed -> {:ok, trimmed}
    end
  end

  defp normalize_required_text(_value, _field), do: {:error, :required}

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_text(_value), do: nil

  defp normalize_optional_map(nil, _field), do: {:ok, nil}
  defp normalize_optional_map(value, _field) when is_map(value), do: {:ok, value}
  defp normalize_optional_map(_value, field), do: {:error, invalid_field_reason(field)}

  defp normalize_string_list(nil, _field), do: {:ok, []}

  defp normalize_string_list(value, field) when is_list(value) do
    if Enum.all?(value, &is_binary/1) do
      {:ok,
       value
       |> Enum.map(&String.trim/1)
       |> Enum.reject(&(&1 == ""))}
    else
      {:error, invalid_field_reason(field)}
    end
  end

  defp normalize_string_list(_value, field), do: {:error, invalid_field_reason(field)}

  defp normalize_non_negative_integer(value, _field) when is_integer(value) and value >= 0,
    do: {:ok, value}

  defp normalize_non_negative_integer(value, _field) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> {:error, :invalid}
    end
  end

  defp normalize_non_negative_integer(_value, _field), do: {:error, :invalid}

  defp normalize_boolean(value, _field) when is_boolean(value), do: {:ok, value}
  defp normalize_boolean(_value, _field), do: {:error, :invalid}

  defp normalize_optional_datetime(nil, _field), do: {:ok, nil}

  defp normalize_optional_datetime(value, field) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, invalid_field_reason(field)}
    end
  end

  defp normalize_optional_datetime(%DateTime{} = value, _field), do: {:ok, value}
  defp normalize_optional_datetime(_value, field), do: {:error, invalid_field_reason(field)}

  defp normalize_slug(value, _field) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed != "" and String.match?(trimmed, @science_task_slug_regex) do
      {:ok, trimmed}
    else
      {:error, :invalid}
    end
  end

  defp normalize_slug(_value, _field), do: {:error, :invalid}

  defp normalize_checklist_status(status) when status in ["pass", "fail", "unknown"], do: status
  defp normalize_checklist_status(_status), do: :invalid

  defp param(attrs, key) when is_map(attrs) do
    case Map.fetch(attrs, key) do
      {:ok, value} ->
        value

      :error ->
        case String.to_existing_atom(key) do
          atom_key -> Map.get(attrs, atom_key)
        end
    end
  rescue
    ArgumentError -> Map.get(attrs, key)
  end

  defp default_checklist do
    Enum.reduce(@checklist_keys, %{}, fn key, acc ->
      Map.put(acc, key, %{status: "unknown", note: nil})
    end)
  end

  defp build_task_attrs(normalized) do
    %{
      science_domain: normalized.science_domain,
      science_field: normalized.science_field,
      task_slug: normalized.task_slug,
      structured_output_shape: normalized.structured_output_shape,
      claimed_expert_time: normalized.claimed_expert_time,
      threshold_rationale: normalized.threshold_rationale,
      anti_cheat_notes: normalized.anti_cheat_notes,
      reproducibility_notes: normalized.reproducibility_notes,
      dependency_pinning_status: normalized.dependency_pinning_status,
      canary_status: normalized.canary_status,
      destination_name: normalized.destination_name,
      packet_hash: normalized.packet_hash,
      packet_files: normalized.packet_files,
      failure_analysis: normalized.failure_analysis
    }
  end

  defp insert_task_node(agent, branch_root, normalized) do
    unique = System.unique_integer([:positive])
    parent_path = branch_root.path || "n#{branch_root.id}"
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %Node{}
    |> Ecto.Changeset.change(%{
      path: "#{parent_path}.n#{unique}",
      depth: (branch_root.depth || 0) + 1,
      seed: @science_seed,
      kind: :eval,
      title: normalized.title,
      slug: normalized.task_slug,
      summary: normalized.summary,
      status: :anchored,
      publish_idempotency_key:
        "science-task:#{normalized.science_domain}:#{normalized.science_field}:#{normalized.task_slug}",
      notebook_source: "# Science Task\n\nTask packet tracked through Harbor review.",
      parent_id: branch_root.id,
      creator_agent_id: agent.id,
      inserted_at: now,
      updated_at: now,
      activity_score: D.new("0")
    })
    |> Ecto.Changeset.unique_constraint(:publish_idempotency_key,
      name: :nodes_publish_idempotency_key_uidx
    )
    |> Repo.insert()
  end

  defp normalize_task_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp normalize_task_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :science_task_invalid_id}
    end
  end

  defp normalize_task_id(_value), do: {:error, :science_task_invalid_id}

  defp invalid_field_reason(field), do: :"science_task_#{field}_invalid"

  defp ensure_branch_root! do
    evals_root = Nodes.create_seed_root!(@science_seed, "Evals Root")

    Node
    |> where(
      [node],
      node.parent_id == ^evals_root.id and node.slug == ^@science_branch_slug and
        node.status == :anchored
    )
    |> limit(1)
    |> Repo.one()
    |> case do
      %Node{} = node ->
        node

      nil ->
        unique = System.unique_integer([:positive])

        %Node{}
        |> Ecto.Changeset.change(%{
          path: "#{evals_root.path || "n#{evals_root.id}"}.n#{unique}",
          depth: (evals_root.depth || 0) + 1,
          seed: @science_seed,
          kind: :eval,
          title: "Science Tasks",
          slug: @science_branch_slug,
          summary:
            "Build science benchmark tasks that carry the packet, evidence, and review notes needed for Harbor review.",
          status: :anchored,
          publish_idempotency_key: "seed:evals:science-tasks",
          notebook_source: "# Science Tasks branch",
          parent_id: evals_root.id,
          creator_agent_id: evals_root.creator_agent_id
        })
        |> Repo.insert!()
    end
  end

  defp put_stage(attrs) do
    workflow_state =
      cond do
        not packet_complete?(attrs.packet_files) ->
          :authoring

        not checklist_all_pass?(attrs.checklist) ->
          :checklist_fix

        not evidence_ready?(attrs) ->
          :checklist_fix

        is_binary(attrs.harbor_pr_url) and attrs.harbor_pr_url != "" and merge_ready?(attrs) ->
          :merge_ready

        is_binary(attrs.harbor_pr_url) and attrs.harbor_pr_url != "" and review_fix?(attrs) ->
          :review_fix

        is_binary(attrs.harbor_pr_url) and attrs.harbor_pr_url != "" ->
          :submitted

        true ->
          :evidence_ready
      end

    Map.put(attrs, :workflow_state, workflow_state)
  end

  defp packet_complete?(packet_files) when is_map(packet_files) do
    validate_required_packet_files(packet_files) == :ok
  end

  defp packet_complete?(_packet_files), do: false

  defp checklist_all_pass?(checklist) when is_map(checklist) do
    Enum.all?(@checklist_keys, fn key ->
      case Map.get(checklist, key) do
        %{"status" => "pass"} -> true
        %{status: "pass"} -> true
        _ -> false
      end
    end)
  end

  defp checklist_all_pass?(_checklist), do: false

  defp evidence_ready?(attrs) do
    run_complete?(attrs.oracle_run) &&
      run_complete?(attrs.frontier_run) &&
      attrs.evidence_packet_hash == attrs.packet_hash
  end

  defp run_complete?(%{"command" => command, "summary" => summary})
       when is_binary(command) and is_binary(summary),
       do: true

  defp run_complete?(%{command: command, summary: summary})
       when is_binary(command) and is_binary(summary),
       do: true

  defp run_complete?(_value), do: false

  defp merge_ready?(attrs) do
    evidence_ready?(attrs) &&
      attrs.open_reviewer_concerns_count == 0 &&
      attrs.any_concern_unanswered == false &&
      attrs.latest_rerun_after_latest_fix == true
  end

  defp review_fix?(attrs) do
    attrs.review_round_count > 0 &&
      (attrs.open_reviewer_concerns_count > 0 ||
         attrs.any_concern_unanswered == true ||
         attrs.latest_rerun_after_latest_fix == false ||
         attrs.evidence_packet_hash != attrs.packet_hash)
  end

  defp current_files_match_latest_evidence?(task) do
    is_binary(task.evidence_packet_hash) and task.evidence_packet_hash == task.packet_hash
  end

  defp public_index_task_card(%ScienceTask{} = task) do
    %{
      node_id: task.node_id,
      title: task.node.title,
      science_domain: task.science_domain,
      science_field: task.science_field,
      task_slug: task.task_slug,
      stage: Atom.to_string(task.workflow_state),
      evidence_label:
        if(current_files_match_latest_evidence?(task),
          do: "proof matches files",
          else: "proof needs refresh"
        )
    }
  end

  defp stage_counts(tasks) do
    Enum.reduce(tasks, %{}, fn task, acc ->
      Map.update(acc, task.stage, 1, &(&1 + 1))
    end)
  end

  defp visible_stages(nil, stage_names), do: stage_names
  defp visible_stages(stage, _stage_names), do: [stage]

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp maybe_put_query(query, _key, nil), do: query
  defp maybe_put_query(query, key, value), do: [{key, value} | query]

  defp packet_hash(packet_files) do
    packet_files
    |> Enum.sort_by(fn {path, _file} -> path end)
    |> Enum.map(fn {path, file} -> {path, file["encoding"], file["content"]} end)
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp parse_limit(params) do
    params
    |> Map.get("limit", 50)
    |> case do
      value when is_integer(value) and value > 0 ->
        min(value, 100)

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed, ""} when parsed > 0 -> min(parsed, 100)
          _ -> 50
        end

      _ ->
        50
    end
  end

  defp maybe_filter_stage(query, nil), do: query

  defp maybe_filter_stage(query, value) when is_binary(value) do
    case Enum.find(ScienceTask.workflow_states(), &(Atom.to_string(&1) == value)) do
      nil -> query
      state -> where(query, [task, _node, _agent], task.workflow_state == ^state)
    end
  end

  defp maybe_filter_stage(query, _value), do: query

  defp maybe_filter_string(query, _field, nil), do: query

  defp maybe_filter_string(query, field, value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      query
    else
      where(query, [task, _node, _agent], field(task, ^field) == ^trimmed)
    end
  end

  defp maybe_filter_string(query, _field, _value), do: query
end
