defmodule TechTree.Benchmarks.Domains.ScienceTask do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Benchmarks.{Capsule, CapsuleVersion}
  alias TechTree.Repo
  alias TechTreeWeb.PublicEncoding

  @stage_names ~w(authoring checklist_fix evidence_ready submitted review_fix merge_ready)
  @visible_states [:approved, :published]

  @spec list_public_tasks(map()) :: [map()]
  def list_public_tasks(params \\ %{}) when is_map(params) do
    limit = TechTree.QueryHelpers.parse_limit(params, 50)
    cursor = TechTree.QueryHelpers.parse_cursor(params)

    Capsule
    |> where([capsule], capsule.domain == :science_task)
    |> where([capsule], capsule.visibility == :public)
    |> where([capsule], capsule.workflow_state in ^@visible_states)
    |> maybe_filter_stage(params["stage"])
    |> maybe_filter_string(:family_ref, params["science_domain"])
    |> maybe_filter_string(:field, params["science_field"])
    |> maybe_before_cursor(cursor)
    |> order_by([capsule],
      asc: capsule.difficulty_label,
      desc: capsule.source_node_id,
      desc: capsule.inserted_at
    )
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&task_detail/1)
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
           stage_names: @stage_names,
           visible_stages: visible_stages(normalized_stage_filter)
         }}

      {:error, :science_task_invalid_stage} ->
        {:error, :science_task_invalid_stage,
         %{
           redirect_href: public_index_href(nil, domain_filter, field_filter)
         }}
    end
  end

  @spec get_public_task(integer() | String.t()) ::
          {:ok, map()} | {:error, :science_task_invalid_id | :science_task_not_found}
  def get_public_task(node_id) do
    with {:ok, normalized_id} <- normalize_task_id(node_id) do
      Capsule
      |> where([capsule], capsule.domain == :science_task)
      |> where([capsule], capsule.visibility == :public)
      |> where([capsule], capsule.workflow_state in ^@visible_states)
      |> where([capsule], capsule.source_node_id == ^normalized_id)
      |> limit(1)
      |> Repo.one()
      |> case do
        %Capsule{} = capsule -> {:ok, task_detail(capsule)}
        nil -> {:error, :science_task_not_found}
      end
    end
  end

  @spec encode_summary(map()) :: map()
  def encode_summary(%{node_id: _node_id} = task) do
    Map.take(task, [
      :node_id,
      :title,
      :summary,
      :science_domain,
      :science_field,
      :task_slug,
      :workflow_state,
      :export_target_path,
      :harbor_pr_url,
      :review_round_count,
      :open_reviewer_concerns_count,
      :current_files_match_latest_evidence,
      :latest_rerun_after_latest_fix,
      :inserted_at,
      :updated_at
    ])
  end

  @spec encode_detail(map()) :: map()
  def encode_detail(%{node_id: _node_id} = task), do: task

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

  @spec stage_names() :: [String.t()]
  def stage_names, do: @stage_names

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
      trimmed == "" -> {:ok, nil}
      trimmed in @stage_names -> {:ok, trimmed}
      true -> {:error, :science_task_invalid_stage}
    end
  end

  def normalize_stage(_value), do: {:error, :science_task_invalid_stage}

  defp task_detail(%Capsule{} = capsule) do
    science = get_in(current_version_source(capsule), ["science_task"]) || %{}
    node = node_payload(capsule, science)
    packet_files = science["packet_files"] || %{}
    packet_hash = science["packet_hash"]
    evidence_packet_hash = science["evidence_packet_hash"]

    %{
      node_id: capsule.source_node_id,
      title: capsule.title,
      summary: capsule.summary_md,
      science_domain: capsule.family_ref,
      science_field: capsule.field,
      task_slug: capsule.provider_ref,
      workflow_state: science["workflow_state"] || "evidence_ready",
      export_target_path: "tasks/#{capsule.family_ref}/#{capsule.field}/#{capsule.provider_ref}",
      harbor_pr_url: science["harbor_pr_url"],
      review_round_count: science["review_round_count"] || 0,
      open_reviewer_concerns_count: science["open_reviewer_concerns_count"] || 0,
      current_files_match_latest_evidence:
        is_binary(evidence_packet_hash) and evidence_packet_hash == packet_hash,
      latest_rerun_after_latest_fix: science["latest_rerun_after_latest_fix"] || false,
      inserted_at: capsule.inserted_at,
      updated_at: capsule.updated_at,
      node: node,
      structured_output_shape: capsule.answer_format,
      claimed_expert_time: science["claimed_expert_time"],
      threshold_rationale: science["threshold_rationale"],
      anti_cheat_notes: science["anti_cheat_notes"],
      reproducibility_notes: science["reproducibility_notes"],
      dependency_pinning_status: science["dependency_pinning_status"],
      canary_status: science["canary_status"],
      destination_name: science["destination_name"],
      packet_hash: packet_hash,
      evidence_packet_hash: evidence_packet_hash,
      packet_files: packet_files,
      checklist: normalize_checklist(science["checklist"] || %{}),
      oracle_run: science["oracle_run"],
      frontier_run: science["frontier_run"],
      failure_analysis: science["failure_analysis"],
      latest_review_follow_up_note: science["latest_review_follow_up_note"],
      last_rerun_at: science["last_rerun_at"],
      latest_fix_at: science["latest_fix_at"],
      any_concern_unanswered: science["any_concern_unanswered"] || false
    }
  end

  defp node_payload(%Capsule{} = capsule, science) do
    case Repo.get(TechTree.Nodes.Node, capsule.source_node_id) do
      nil -> science["node"]
      node -> PublicEncoding.encode_node(Repo.preload(node, :creator_agent))
    end
  end

  defp public_index_task_card(task) do
    %{
      node_id: task.node_id,
      title: task.title,
      science_domain: task.science_domain,
      science_field: task.science_field,
      task_slug: task.task_slug,
      stage: task.workflow_state,
      evidence_label:
        if(task.current_files_match_latest_evidence,
          do: "proof matches files",
          else: "proof needs refresh"
        )
    }
  end

  defp maybe_filter_stage(query, nil), do: query

  defp maybe_filter_stage(query, stage) do
    where(query, [capsule], capsule.difficulty_label == ^stage)
  end

  defp current_version_source(%Capsule{} = capsule) do
    CapsuleVersion
    |> where([version], version.capsule_id == ^capsule.capsule_id)
    |> where([version], version.version_id == ^capsule.current_version_id)
    |> limit(1)
    |> Repo.one()
    |> case do
      %CapsuleVersion{} = version -> version.capsule_source || %{}
      nil -> %{}
    end
  end

  defp maybe_filter_string(query, _field, nil), do: query

  defp maybe_filter_string(query, field, value) do
    where(query, [record], field(record, ^field) == ^value)
  end

  defp maybe_before_cursor(query, nil), do: query

  defp maybe_before_cursor(query, cursor) when is_integer(cursor) do
    where(query, [capsule], capsule.source_node_id < ^cursor)
  end

  defp normalize_task_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp normalize_task_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :science_task_invalid_id}
    end
  end

  defp normalize_task_id(_value), do: {:error, :science_task_invalid_id}

  defp normalize_checklist(checklist) when is_map(checklist) do
    Map.new(checklist, fn {key, entry} ->
      normalized =
        case entry do
          %{"status" => _status} -> entry
          %{status: status, note: note} -> %{"status" => status, "note" => note}
          _ -> %{"status" => "unknown", "note" => nil}
        end

      {key, normalized}
    end)
  end

  defp normalize_checklist(_checklist), do: %{}

  defp stage_counts(tasks) do
    Enum.reduce(tasks, %{}, fn task, acc ->
      Map.update(acc, task.stage, 1, &(&1 + 1))
    end)
  end

  defp visible_stages(nil), do: @stage_names
  defp visible_stages(stage), do: [stage]

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp maybe_put_query(query, _key, nil), do: query
  defp maybe_put_query(query, key, value), do: [{key, value} | query]
end
