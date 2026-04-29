defmodule TechTree.BBH.Presentation do
  @moduledoc false

  alias TechTree.BBH
  alias TechTree.BBH.WallCopy

  @active_window_minutes 30
  @hot_window_minutes 45
  @feed_limit 12
  @recent_runs_limit 6
  @official_ranking_limit 6
  @epoch ~U[1970-01-01 00:00:00Z]
  @wall_splits ~w(climb benchmark challenge)

  @spec leaderboard_page(map()) :: map()
  def leaderboard_page(params \\ %{}) do
    selected_capsule_id = params["selected_capsule_id"] || params[:selected_capsule_id]
    inventory_capsules = BBH.list_capsules(%{split: @wall_splits})
    runs = BBH.list_runs(%{split: @wall_splits})
    validations_by_run_id = Map.new(runs, fn run -> {run.run_id, run.validations || []} end)
    runs_by_capsule_id = Enum.group_by(runs, & &1.capsule_id)
    capsules = build_capsules(inventory_capsules, runs_by_capsule_id, validations_by_run_id)
    benchmark_entries = official_ranking_entries("benchmark")

    benchmark_top_score =
      benchmark_entries |> List.first() |> then(&if(&1, do: &1.score || 0.0, else: 0.0))

    selected_capsule = selected_capsule(capsules, selected_capsule_id)
    official_boards = official_boards()

    rendered_capsules =
      capsules |> layout_capsules() |> decorate_challenge_capsules(benchmark_top_score)

    lane_sections = WallCopy.lane_sections(rendered_capsules)

    %{
      split: "wall",
      total_entries: Enum.reduce(official_boards, 0, &(&1.count + &2)),
      total_capsules: length(rendered_capsules),
      top_score:
        official_boards
        |> Enum.flat_map(& &1.entries)
        |> Enum.map(&(&1.score || 0.0))
        |> Enum.max(fn -> 0.0 end),
      capsules: rendered_capsules,
      selected_capsule_id: selected_capsule && selected_capsule.capsule_id,
      drilldown_capsule:
        selected_capsule &&
          build_drilldown(
            selected_capsule,
            Map.get(runs_by_capsule_id, selected_capsule.capsule_id, [])
          ),
      lane_sections: lane_sections,
      lane_counts: Map.new(lane_sections, &{&1.key, &1.count}),
      event_feed_items: build_event_feed(capsules),
      official_boards: official_boards,
      wall_copy: WallCopy.page_copy()
    }
  end

  def lane_sections(capsules), do: WallCopy.lane_sections(capsules)

  @spec run_page(String.t()) :: {:ok, map()} | :error
  def run_page(run_id) when is_binary(run_id) do
    case BBH.get_run(run_id) do
      nil ->
        :error

      %{run: run, capsule: capsule, genome: genome, validations: validations} ->
        split = run.split || "benchmark"
        lane_key = split_lane_key(split)
        latest_validation = List.first(validations)
        status_label = review_state_label(split, latest_validation)
        score = run_score(run)

        {:ok,
         %{
           run: %{
             id: run.run_id,
             artifact_id: run.capsule_id,
             title: genome_name(genome),
             split: split,
             capsule_badge_kind: badge_kind(split),
             capsule_title: capsule.title || short_capsule_label(run.capsule_id),
             score_percent: score,
             score_label: format_number(score, "%"),
             review_state: review_state_label(split, latest_validation),
             lane_key: lane_key,
             lane_label: lane_label(lane_key),
             operator_lane_tag: operator_lane_tag(lane_key),
             status_label: status_label,
             lane_subtitle: run_subtitle(split, status_label),
             ledger_boundary_note: ledger_boundary_note(split, status_label),
             reproducible?: review_state_label(split, latest_validation) == "validated",
             genome: %{
               fingerprint: genome.genome_id,
               name: genome_name(genome),
               model: genome.model_id,
               router: genome.tool_profile,
               planner: nil,
               critic: nil,
               tool_policy: genome.tool_profile,
               runtime: genome.runtime_image
             },
             execution: %{
               runtime_image: genome.runtime_image,
               python_version: nil,
               platform: nil
             },
             outputs: outputs_files(run),
             artifact_source: run.artifact_source,
             publication_review_id: capsule.publication_review_id,
             published_at: capsule.published_at && format_timestamp(capsule.published_at),
             certificate_status: enum_value(capsule.certificate_status || :none),
             certificate_review_id: capsule.certificate_review_id,
             certificate_expires_at:
               capsule.certificate_expires_at && format_timestamp(capsule.certificate_expires_at)
           },
           validations: Enum.map(validations, &decorate_validation/1),
           score_cards: score_cards(score, lane_key, status_label, validations),
           execution_rows: execution_rows(run, genome),
           artifact_rows: artifact_rows(capsule, run)
         }}
    end
  end

  defp build_capsules(capsule_inventory, runs_by_capsule_id, validations_by_run_id) do
    now = DateTime.utc_now()

    capsule_inventory
    |> Enum.map(fn capsule ->
      sorted_runs = sort_runs_desc(Map.get(runs_by_capsule_id, capsule.capsule_id, []))
      latest_run = List.first(sorted_runs)
      active_runs = active_runs(sorted_runs, now)
      active_agents = active_agents(active_runs)
      current_best_run = best_run(sorted_runs) || latest_run

      confirmed_runs =
        Enum.filter(sorted_runs, &confirmed_run?(&1, validations_by_run_id[&1.run_id] || []))

      latest_validated_run = best_run(confirmed_runs)
      latest_event = latest_capsule_event(sorted_runs, validations_by_run_id, active_agents)
      active_agent_count = map_size(active_agents)
      lane_key = split_lane_key(capsule.split)
      run_count = length(sorted_runs)

      %{
        capsule_id: capsule.capsule_id,
        title: capsule.title || short_capsule_label(capsule.capsule_id),
        subtitle: capsule.hypothesis || "Canonical BBH capsule",
        badge_kind: badge_kind(capsule.split),
        lane_key: lane_key,
        lane_label: lane_label(lane_key),
        operator_lane_tag: operator_lane_tag(lane_key),
        best_score: current_best_run && run_score(current_best_run),
        best_score_label: format_number(current_best_run && run_score(current_best_run), "%"),
        best_validated_score: latest_validated_run && run_score(latest_validated_run),
        best_validated_score_label:
          format_number(latest_validated_run && run_score(latest_validated_run), "%"),
        active_agent_count: active_agent_count,
        active_agents: Map.values(active_agents),
        route_maturity: route_maturity(active_agent_count, run_count, latest_validated_run),
        current_best_run_id: current_best_run && current_best_run.run_id,
        latest_validated_run_id: latest_validated_run && latest_validated_run.run_id,
        current_best_run: current_best_run,
        latest_validated_run: latest_validated_run,
        latest_run: latest_run,
        run_count: run_count,
        publication_review_id: capsule.publication_review_id,
        publication_artifact_id: capsule.publication_artifact_id,
        published_at: capsule.published_at,
        certificate_status: enum_value(capsule.certificate_status || :none),
        certificate_review_id: capsule.certificate_review_id,
        certificate_expires_at: capsule.certificate_expires_at,
        review_open_count: BBH.review_open_count(capsule.capsule_id),
        recent_runs: Enum.take(sorted_runs, @recent_runs_limit),
        latest_outputs: latest_outputs(current_best_run || latest_validated_run || latest_run),
        best_state_label:
          best_state_label(capsule, current_best_run, latest_validated_run, validations_by_run_id),
        last_event_kind: latest_event.kind,
        last_event_at: latest_event.occurred_at,
        last_event_at_label: format_timestamp(latest_event.occurred_at),
        freshness_label: freshness_label(latest_event.occurred_at),
        last_event_headline: latest_event.headline,
        last_event_run_id: latest_event.run_id,
        is_hot: hot_capsule?(latest_event.occurred_at, active_agent_count, current_best_run)
      }
    end)
    |> Enum.sort_by(&capsule_sort_key/1, :desc)
  end

  defp selected_capsule([], _selected_capsule_id), do: nil

  defp selected_capsule(capsules, selected_capsule_id) do
    Enum.find(capsules, &(&1.capsule_id == selected_capsule_id)) ||
      Enum.max_by(capsules, &capsule_hotness/1, fn -> List.first(capsules) end)
  end

  defp build_drilldown(capsule, runs) do
    %{
      capsule_id: capsule.capsule_id,
      title: capsule.title,
      subtitle: capsule.subtitle,
      badge_kind: capsule.badge_kind,
      lane_key: capsule.lane_key,
      lane_label: capsule.lane_label,
      operator_lane_tag: capsule.operator_lane_tag,
      best_state_label: capsule.best_state_label,
      route_maturity: capsule.route_maturity,
      active_agents: capsule.active_agents,
      active_agent_count: capsule.active_agent_count,
      freshness_label: capsule.freshness_label,
      current_best_genome:
        capsule.current_best_run &&
          %{
            name: genome_name(capsule.current_best_run.genome),
            model: capsule.current_best_run.genome.model_id,
            router: capsule.current_best_run.genome.tool_profile,
            fingerprint: capsule.current_best_run.genome.genome_id
          },
      current_best_run:
        capsule.current_best_run &&
          run_summary(capsule.current_best_run,
            label: "Current best",
            review_state:
              review_state_label(
                capsule_split(capsule.current_best_run),
                List.first(capsule.current_best_run.validations || [])
              ),
            lane_key: capsule.lane_key
          ),
      latest_validated_run:
        capsule.latest_validated_run &&
          run_summary(capsule.latest_validated_run,
            label: "Latest validated",
            review_state: "validated",
            lane_key: split_lane_key(capsule_split(capsule.latest_validated_run))
          ),
      recent_runs:
        Enum.map(capsule.recent_runs, fn run ->
          run_summary(run,
            label: "Recent run",
            review_state: nil,
            lane_key: capsule.lane_key
          )
        end),
      latest_artifact: %{
        title: capsule.title,
        summary: capsule.subtitle,
        notebook_ref: capsule.latest_outputs.primary_output,
        verdict_ref: capsule.latest_outputs.verdict_ref,
        log_ref: capsule.latest_outputs.log_ref
      },
      run_count: length(runs),
      challenge_status: Map.get(capsule, :challenge_status),
      challenge_attempts: Map.get(capsule, :challenge_attempts, 0),
      publication_age_label: Map.get(capsule, :publication_age_label),
      publication_review_id: capsule.publication_review_id,
      certificate_status: enum_value(capsule.certificate_status),
      certificate_review_id: capsule.certificate_review_id,
      certificate_expires_at:
        capsule.certificate_expires_at && freshness_label(capsule.certificate_expires_at),
      review_open_count: capsule.review_open_count,
      review_claim_hint:
        if(capsule.review_open_count > 0,
          do: "regents techtree review claim <request-id>",
          else: nil
        )
    }
  end

  defp build_event_feed(capsules) do
    capsules
    |> Enum.flat_map(&capsule_feed_items/1)
    |> Enum.sort_by(&datetime_sort_key(&1.occurred_at), :desc)
    |> Enum.take(@feed_limit)
  end

  defp capsule_feed_items(capsule) do
    base =
      if capsule.last_event_at do
        [
          %{
            id:
              "capsule:#{capsule.capsule_id}:#{capsule.last_event_kind}:#{datetime_sort_key(capsule.last_event_at)}",
            kind: capsule.last_event_kind,
            capsule_id: capsule.capsule_id,
            run_id: capsule.last_event_run_id,
            actor_label: capsule.active_agents |> List.first() |> then(&(&1 && &1.label)),
            headline: capsule.last_event_headline,
            occurred_at: capsule.last_event_at
          }
        ]
      else
        []
      end

    challenge_items =
      if capsule.lane_key == :challenge and capsule.published_at do
        [
          %{
            id:
              "capsule:#{capsule.capsule_id}:challenge-revealed:#{datetime_sort_key(capsule.published_at)}",
            kind: :challenge_revealed,
            capsule_id: capsule.capsule_id,
            run_id: nil,
            actor_label: nil,
            headline: "#{capsule.title} landed as a reviewed public challenge route",
            occurred_at: capsule.published_at
          }
        ]
      else
        []
      end

    active_items =
      if (capsule.active_agent_count > 0 and capsule.latest_run) && capsule.latest_run.inserted_at do
        [
          %{
            id: "capsule:#{capsule.capsule_id}:pickup:#{capsule.latest_run.run_id}",
            kind: :agent_pickup,
            capsule_id: capsule.capsule_id,
            run_id: capsule.latest_run.run_id,
            actor_label: display_name(capsule.latest_run),
            headline: "#{display_name(capsule.latest_run)} picked up #{capsule.title}",
            occurred_at: capsule.latest_run.inserted_at
          }
        ]
      else
        []
      end

    base ++ challenge_items ++ active_items
  end

  defp official_boards do
    Enum.map(WallCopy.official_board_specs(), &build_official_board/1)
  end

  defp build_official_board(spec) do
    split = Atom.to_string(spec.key)
    entries = official_ranking_entries(split)

    %{
      key: spec.key,
      split: split,
      title: spec.title,
      intro_kicker: spec.intro_kicker,
      intro_note: spec.intro_note,
      empty_message: spec.empty_message,
      count: length(entries),
      entries: entries
    }
  end

  defp official_ranking_entries(split) do
    BBH.leaderboard(%{split: split}).entries
    |> Enum.map(&decorate_entry/1)
    |> Enum.take(@official_ranking_limit)
  end

  defp layout_capsules(capsules) do
    columns = column_count(length(capsules))

    Enum.with_index(capsules, 0)
    |> Enum.map(fn {capsule, index} ->
      row = div(index, columns)
      col = rem(index, columns)

      capsule
      |> Map.put(:layout_row, row)
      |> Map.put(:layout_col, col)
      |> Map.put(:layout_offset?, rem(row, 2) == 1)
      |> Map.put(
        :score_percent,
        score_percent(capsule.best_validated_score || capsule.best_score)
      )
      |> Map.put(:validated_percent, score_percent(capsule.best_validated_score))
      |> Map.put(:pip_count, min(capsule.active_agent_count, 6))
    end)
  end

  defp decorate_challenge_capsules(capsules, benchmark_top_score) do
    Enum.map(capsules, fn capsule ->
      if capsule.lane_key == :challenge do
        {challenge_status, publication_age_label} = challenge_status(capsule, benchmark_top_score)

        capsule
        |> Map.put(:challenge_status, challenge_status)
        |> Map.put(:challenge_attempts, capsule.run_count)
        |> Map.put(:publication_age_label, publication_age_label)
      else
        capsule
        |> Map.put(:challenge_status, nil)
        |> Map.put(:challenge_attempts, 0)
        |> Map.put(:publication_age_label, nil)
      end
    end)
  end

  defp latest_capsule_event(sorted_runs, validations_by_run_id, active_agents) do
    ascending_runs = sort_runs_asc(sorted_runs)
    personal_best_ids = personal_best_run_ids(ascending_runs)
    capsule_best_ids = capsule_best_run_ids(ascending_runs)
    latest_run = List.first(sorted_runs)

    validation_events =
      sorted_runs
      |> Enum.flat_map(fn run ->
        Enum.map(validations_by_run_id[run.run_id] || [], fn validation -> {run, validation} end)
      end)
      |> Enum.map(fn {run, validation} ->
        kind =
          cond do
            validation.result == :confirmed and MapSet.member?(capsule_best_ids, run.run_id) ->
              :validated_official_best

            validation.result == :confirmed ->
              :validation_confirmed

            true ->
              :validation_rejected
          end

        {validation.inserted_at, kind, run, validation}
      end)

    run_events =
      Enum.map(ascending_runs, fn run ->
        kind =
          cond do
            MapSet.member?(capsule_best_ids, run.run_id) -> :capsule_best
            MapSet.member?(personal_best_ids, run.run_id) -> :personal_best
            run.status == :failed -> :run_failed
            true -> :run_submitted
          end

        {run.inserted_at, kind, run, nil}
      end)

    case Enum.max_by(
           validation_events ++ run_events,
           fn {occurred_at, _kind, _run, _validation} -> datetime_sort_key(occurred_at) end,
           fn -> nil end
         ) do
      nil ->
        idle_event(latest_run, active_agents)

      {occurred_at, kind, run, validation} ->
        %{
          kind: kind,
          occurred_at: occurred_at,
          headline: event_headline(kind, run, validation),
          run_id: run.run_id
        }
    end
  end

  defp idle_event(latest_run, active_agents) do
    lane = latest_run && operator_lane_tag(split_lane_key(capsule_split(latest_run)))

    cond do
      map_size(active_agents) > 0 and latest_run ->
        %{
          kind: :agent_pickup,
          occurred_at: latest_run.inserted_at,
          headline:
            "#{display_name(latest_run)} picked up #{lane} on #{short_capsule_label(latest_run.capsule_id)}",
          run_id: latest_run.run_id
        }

      latest_run && latest_run.inserted_at &&
          DateTime.diff(DateTime.utc_now(), latest_run.inserted_at, :minute) >
            @active_window_minutes ->
        %{
          kind: :capsule_cold,
          occurred_at: latest_run.inserted_at,
          headline: "#{short_capsule_label(latest_run.capsule_id)} went quiet on the wall",
          run_id: latest_run.run_id
        }

      latest_run ->
        %{
          kind: :idle,
          occurred_at: latest_run.inserted_at,
          headline:
            "#{display_name(latest_run)} is holding #{short_capsule_label(latest_run.capsule_id)} in #{lane}",
          run_id: latest_run.run_id
        }

      true ->
        %{kind: :idle, occurred_at: nil, headline: "Waiting for the first BBH run", run_id: nil}
    end
  end

  defp personal_best_run_ids(runs) do
    {_, ids} =
      Enum.reduce(runs, {%{}, MapSet.new()}, fn run, {best_by_executor, ids} ->
        current_best = Map.get(best_by_executor, run.genome_id, -1.0)
        next_score = run_score(run)

        if next_score > current_best do
          {Map.put(best_by_executor, run.genome_id, next_score), MapSet.put(ids, run.run_id)}
        else
          {best_by_executor, ids}
        end
      end)

    ids
  end

  defp capsule_best_run_ids(runs) do
    {_, ids} =
      Enum.reduce(runs, {-1.0, MapSet.new()}, fn run, {best_score, ids} ->
        next_score = run_score(run)

        if next_score > best_score do
          {next_score, MapSet.put(ids, run.run_id)}
        else
          {best_score, ids}
        end
      end)

    ids
  end

  defp route_maturity(active_agent_count, run_count, latest_validated_run) do
    cond do
      active_agent_count >= 4 -> :saturated
      active_agent_count >= 2 -> :crowded
      is_nil(latest_validated_run) and run_count <= 1 -> :new
      true -> :active
    end
  end

  defp active_runs(runs, now) do
    Enum.filter(runs, fn run ->
      run.inserted_at && DateTime.diff(now, run.inserted_at, :minute) <= @active_window_minutes
    end)
  end

  defp active_agents(runs) do
    Enum.reduce(runs, %{}, fn run, acc ->
      Map.put_new(acc, run.genome_id, %{id: run.genome_id, label: display_name(run)})
    end)
  end

  defp hot_capsule?(nil, active_agent_count, current_best_run),
    do: active_agent_count > 0 or !!current_best_run

  defp hot_capsule?(occurred_at, active_agent_count, current_best_run) do
    active_agent_count > 0 or
      DateTime.diff(DateTime.utc_now(), occurred_at, :minute) <= @hot_window_minutes or
      !!current_best_run
  end

  defp capsule_hotness(capsule) do
    {
      bool_sort(capsule.is_hot),
      capsule.active_agent_count,
      datetime_sort_key(capsule.last_event_at),
      capsule.best_validated_score || capsule.best_score || 0.0
    }
  end

  defp capsule_sort_key(capsule) do
    {
      bool_sort(capsule.is_hot),
      capsule.active_agent_count,
      datetime_sort_key(capsule.last_event_at),
      capsule.best_validated_score || capsule.best_score || 0.0
    }
  end

  defp best_run([]), do: nil
  defp best_run(runs), do: Enum.max_by(runs, &run_score/1, fn -> nil end)

  defp sort_runs_desc(runs), do: Enum.sort_by(runs, &datetime_sort_key(&1.inserted_at), :desc)
  defp sort_runs_asc(runs), do: Enum.sort_by(runs, &datetime_sort_key(&1.inserted_at), :asc)

  defp datetime_sort_key(nil), do: DateTime.to_unix(@epoch, :microsecond)
  defp datetime_sort_key(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)

  defp bool_sort(true), do: 1
  defp bool_sort(_value), do: 0

  defp badge_kind("climb"), do: :climb
  defp badge_kind("challenge"), do: :challenge
  defp badge_kind(_split), do: :benchmark

  defp lane_label(:practice), do: "Practice"
  defp lane_label(:proving), do: "Proving"
  defp lane_label(:challenge), do: "Challenge"
  defp lane_label(_lane), do: "Practice"

  defp split_lane_key("benchmark"), do: :proving
  defp split_lane_key("challenge"), do: :challenge
  defp split_lane_key(_split), do: :practice

  defp operator_lane_tag(:practice), do: "climb"
  defp operator_lane_tag(:proving), do: "benchmark"
  defp operator_lane_tag(:challenge), do: "challenge"
  defp operator_lane_tag(_lane), do: "climb"

  defp run_summary(run, opts) do
    validation = Keyword.get(opts, :review) || List.first(run.validations || [])
    lane_key = Keyword.get(opts, :lane_key, :practice)
    split = capsule_split(run)

    %{
      id: run.run_id,
      label: Keyword.fetch!(opts, :label),
      review_state: Keyword.get(opts, :review_state) || review_state_label(split, validation),
      score_label: format_number(run_score(run), "%"),
      inserted_at: run.inserted_at,
      inserted_at_label: format_timestamp(run.inserted_at),
      freshness_label: freshness_label(run.inserted_at),
      display_name: display_name(run),
      lane_label: lane_label(lane_key)
    }
  end

  defp capsule_split(nil), do: "climb"
  defp capsule_split(run), do: run.split || "climb"

  defp latest_outputs(nil), do: %{primary_output: nil, verdict_ref: nil, log_ref: nil}

  defp latest_outputs(run) do
    paths = get_in(run.run_source || %{}, ["paths"]) || %{}

    %{
      primary_output: paths["analysis_path"],
      verdict_ref: paths["verdict_path"],
      log_ref: paths["log_path"]
    }
  end

  defp outputs_files(run) do
    paths = get_in(run.run_source || %{}, ["paths"]) || %{}

    Enum.reject(
      [
        paths["analysis_path"],
        paths["verdict_path"],
        paths["final_answer_path"],
        paths["report_path"],
        paths["log_path"],
        paths["genome_path"]
      ],
      &is_nil/1
    )
  end

  defp display_name(run), do: genome_name(run.genome)

  defp genome_name(nil), do: "unknown genome"
  defp genome_name(genome), do: genome.label || genome.genome_id

  defp short_capsule_label("0x" <> rest), do: "cap_" <> String.slice(rest, -6, 6)
  defp short_capsule_label(value) when is_binary(value), do: value

  defp confirmed_run?(run, validations) do
    Enum.any?(validations, fn validation ->
      validation.run_id == run.run_id and validation.role == :official and
        validation.method == :replay and validation.result == :confirmed
    end)
  end

  defp review_state_label(_split, %{result: :confirmed}), do: "validated"
  defp review_state_label("climb", _review), do: "self-reported"
  defp review_state_label(_split, _review), do: "pending validation"

  defp score_percent(nil), do: 0.0
  defp score_percent(score), do: max(min(score / 100.0, 1.0), 0.0)

  defp column_count(count) when count <= 4, do: 2
  defp column_count(count) when count <= 9, do: 3
  defp column_count(count) when count <= 16, do: 4
  defp column_count(_count), do: 5

  defp event_headline(:validated_official_best, run, _validation) do
    "#{display_name(run)} cleared replay on #{short_capsule_label(run.capsule_id)}"
  end

  defp event_headline(:validation_confirmed, run, _validation) do
    "benchmark replay confirmed #{display_name(run)} on #{short_capsule_label(run.capsule_id)}"
  end

  defp event_headline(:validation_rejected, run, _validation) do
    "replay rejected #{display_name(run)} on #{short_capsule_label(run.capsule_id)}"
  end

  defp event_headline(:capsule_best, run, _validation) do
    "new wall mark on #{short_capsule_label(run.capsule_id)} by #{display_name(run)}"
  end

  defp event_headline(:personal_best, run, _validation) do
    "#{display_name(run)} improved on #{short_capsule_label(run.capsule_id)}"
  end

  defp event_headline(:run_failed, run, _validation) do
    "#{display_name(run)} dropped a wall run on #{short_capsule_label(run.capsule_id)}"
  end

  defp event_headline(:run_submitted, run, _validation) do
    "#{display_name(run)} entered #{operator_lane_tag(split_lane_key(capsule_split(run)))} on #{short_capsule_label(run.capsule_id)}"
  end

  defp event_headline(_kind, run, _validation) do
    "#{display_name(run)} touched #{short_capsule_label(run.capsule_id)}"
  end

  defp decorate_entry(entry) do
    entry
    |> Map.put(:node_id, entry.run_id)
    |> Map.put(:display_name, entry.name)
    |> Map.put(:score, entry.score_percent)
    |> Map.put(:score_label, format_number(entry.score_percent, "%"))
    |> Map.put(:hit_rate_label, "reproduced")
    |> Map.put(:reproducibility_label, "yes")
    |> Map.put(:review_count, entry.validated_runs)
    |> Map.put(:latency_label, "n/a")
    |> Map.put(:cost_label, "n/a")
  end

  defp score_cards(score, lane_key, status_label, validations) do
    [
      %{id: "score", label: "Score", value: format_number(score, "%")},
      %{id: "lane", label: "Wall lane", value: lane_label(lane_key)},
      %{id: "status", label: "Validation state", value: status_label},
      %{id: "replays", label: "Replays", value: Integer.to_string(length(validations))}
    ]
  end

  defp execution_rows(run, genome) do
    run_source = run.run_source || %{}
    solver = Map.get(run_source, "solver") || %{}
    search = Map.get(run_source, "search") || %{}
    evaluator = Map.get(run_source, "evaluator") || %{}

    [
      %{
        id: "backend",
        label: "Runner",
        value: stringify(run.executor_type)
      },
      %{
        id: "image",
        label: "Runtime image",
        value: stringify(genome.runtime_image)
      },
      %{
        id: "solver",
        label: "Solver",
        value: stringify(solver["kind"])
      },
      %{
        id: "search_algorithm",
        label: "Search algorithm",
        value: stringify(search["algorithm"])
      },
      %{
        id: "search_budget",
        label: "Search budget",
        value: stringify(search["budget"])
      },
      %{
        id: "evaluator",
        label: "Evaluator",
        value: stringify(evaluator["kind"])
      },
      %{
        id: "dataset_ref",
        label: "Dataset",
        value: stringify(evaluator["dataset_ref"])
      },
      %{
        id: "score_source",
        label: "Score source",
        value: stringify(run.score_source)
      },
      %{
        id: "python",
        label: "Python version",
        value: "n/a"
      }
    ]
  end

  defp artifact_rows(capsule, run) do
    [
      {"capsule_id", capsule && capsule.capsule_id},
      {"capsule_title", capsule && capsule.title},
      {"capsule_summary", capsule && capsule.hypothesis},
      {"publication_review_id", capsule && capsule.publication_review_id},
      {"published_at", capsule && capsule.published_at && format_timestamp(capsule.published_at)},
      {"certificate_status", capsule && enum_value(capsule.certificate_status)},
      {"certificate_review_id", capsule && capsule.certificate_review_id},
      {"certificate_expires_at",
       capsule && capsule.certificate_expires_at &&
         format_timestamp(capsule.certificate_expires_at)},
      {"primary_output", get_in(run.run_source || %{}, ["paths", "analysis_path"])},
      {"verdict_ref", get_in(run.run_source || %{}, ["paths", "verdict_path"])},
      {"log_ref", get_in(run.run_source || %{}, ["paths", "log_path"])}
    ]
    |> Enum.map(fn {key, value} ->
      %{
        id: to_string(key),
        label: key |> to_string() |> String.replace("_", " "),
        value: stringify(value)
      }
    end)
    |> Enum.reject(&(&1.value == "n/a"))
  end

  defp decorate_validation(validation) do
    review_bbh =
      case validation.review_source do
        %{"bbh" => %{} = bbh} -> bbh
        _ -> %{}
      end

    %{
      id: validation.validation_id,
      validator_id: validation.role || "official",
      validator_kind: enum_value(validation.method),
      status: enum_value(validation.result),
      status_label:
        case validation.result do
          :confirmed -> "validated"
          :rejected -> "rejected"
          _ -> "pending validation"
        end,
      reproducible: validation.result == :confirmed,
      artifact_match: Map.get(review_bbh, "artifact_match", validation.result == :confirmed),
      score_match: Map.get(review_bbh, "score_match", validation.result == :confirmed)
    }
  end

  defp format_number(value, suffix) when is_number(value),
    do: :erlang.float_to_binary(value * 1.0, decimals: 2) <> suffix

  defp format_number(_value, _suffix), do: "n/a"

  defp format_timestamp(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %-d %H:%M UTC")
  end

  defp format_timestamp(nil), do: "No activity yet"

  defp freshness_label(nil), do: "No activity yet"

  defp freshness_label(%DateTime{} = datetime) do
    minutes = max(DateTime.diff(DateTime.utc_now(), datetime, :minute), 0)

    cond do
      minutes < 1 -> "just now"
      minutes < 60 -> "#{minutes}m ago"
      minutes < 1_440 -> "#{div(minutes, 60)}h ago"
      true -> "#{div(minutes, 1_440)}d ago"
    end
  end

  defp best_state_review(nil, _latest_validated_run, _validations_by_run_id), do: nil

  defp best_state_review(current_best_run, latest_validated_run, validations_by_run_id) do
    cond do
      latest_validated_run && current_best_run &&
          latest_validated_run.run_id == current_best_run.run_id ->
        List.first(validations_by_run_id[current_best_run.run_id] || [])

      true ->
        List.first(validations_by_run_id[current_best_run.run_id] || [])
    end
  end

  defp stringify(value) when is_binary(value) and value != "", do: value
  defp stringify(value) when is_number(value), do: to_string(value)
  defp stringify(true), do: "true"
  defp stringify(false), do: "false"
  defp stringify(_value), do: "n/a"

  defp best_state_label(_capsule, nil, nil, _validations_by_run_id), do: "awaiting first run"

  defp best_state_label(capsule, current_best_run, latest_validated_run, validations_by_run_id) do
    review_state_label(
      capsule.split,
      best_state_review(current_best_run, latest_validated_run, validations_by_run_id)
    )
  end

  defp run_score(nil), do: nil
  defp run_score(run), do: (run.normalized_score || 0.0) * 100.0

  defp challenge_status(capsule, benchmark_top_score) do
    cond do
      is_nil(capsule.published_at) ->
        {"awaiting public review", nil}

      capsule.best_validated_score && benchmark_top_score > 0.0 &&
          capsule.best_validated_score >= benchmark_top_score ->
        {"champion-breaking route", freshness_label(capsule.published_at)}

      capsule.best_validated_score ->
        {"confirmed public frontier", freshness_label(capsule.published_at)}

      capsule.run_count > 0 ->
        {"pending replay on public route", freshness_label(capsule.published_at)}

      true ->
        {"reviewed route, waiting for first attempt", freshness_label(capsule.published_at)}
    end
  end

  defp run_subtitle("climb", status_label),
    do:
      "Practice lane run, currently #{status_label}. Full-feedback work stays public on the wall while replay catches up."

  defp run_subtitle("challenge", status_label),
    do:
      "Challenge lane run, currently #{status_label}. Public reviewed frontier work stays visible even while the official board sections stay empty in the v0.1 beta."

  defp run_subtitle(_split, status_label),
    do:
      "Proving lane run, currently #{status_label}. This is the apples-to-apples comparison lane, but the official board sections stay empty in the v0.1 beta."

  defp ledger_boundary_note("climb", status_label),
    do:
      "This run sits in Practice and is currently marked #{status_label}. Practice stays visible on the wall, and the official board sections stay intentionally empty in the v0.1 beta."

  defp ledger_boundary_note("challenge", status_label),
    do:
      "This run sits in Challenge and is currently marked #{status_label}. Challenge stays public and reviewed on the frontier board while the official board sections stay intentionally empty in the v0.1 beta."

  defp ledger_boundary_note(_split, status_label),
    do:
      "This run sits in Proving and is currently marked #{status_label}. In the v0.1 beta, the public wall and run page are the visible destination while the official board sections stay empty."

  defp enum_value(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_value(value), do: value
end
