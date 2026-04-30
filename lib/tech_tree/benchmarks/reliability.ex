defmodule TechTree.Benchmarks.Reliability do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Benchmarks.{Attempt, ReliabilitySummary, Validation}
  alias TechTree.Repo

  @single_repeat_group "single"
  @official_rejection_results [:rejected, :mixed, :needs_revision]

  @spec single_repeat_group() :: String.t()
  def single_repeat_group, do: @single_repeat_group

  @spec recompute_group(String.t(), String.t(), String.t(), String.t(), module()) ::
          {:ok, ReliabilitySummary.t() | nil} | {:error, Ecto.Changeset.t()}
  def recompute_group(capsule_id, version_id, harness_id, repeat_group_id, repo \\ Repo)
      when is_binary(capsule_id) and is_binary(version_id) and is_binary(harness_id) and
             is_binary(repeat_group_id) do
    attempts =
      Attempt
      |> where([attempt], attempt.capsule_id == ^capsule_id)
      |> where([attempt], attempt.version_id == ^version_id)
      |> where([attempt], attempt.harness_id == ^harness_id)
      |> where(
        [attempt],
        fragment(
          "coalesce(?, ?) = ?",
          attempt.repeat_group_id,
          ^@single_repeat_group,
          ^repeat_group_id
        )
      )
      |> order_by([attempt], asc: attempt.attempt_ordinal, asc: attempt.inserted_at)
      |> preload(:validations)
      |> repo.all()

    case attempts do
      [] ->
        {:ok, nil}

      [_ | _] ->
        attrs = summary_attrs(capsule_id, version_id, harness_id, repeat_group_id, attempts)

        %ReliabilitySummary{}
        |> ReliabilitySummary.changeset(attrs)
        |> repo.insert(
          on_conflict:
            {:replace,
             [
               :attempt_count,
               :solve_count,
               :solve_rate,
               :reliable,
               :brittle,
               :answer_variance,
               :median_runtime_seconds,
               :p90_runtime_seconds,
               :median_cost_usd_micros,
               :validation_confirmed_count,
               :last_attempt_at,
               :updated_at
             ]},
          conflict_target: [:capsule_id, :version_id, :harness_id, :repeat_group_id],
          returning: true
        )
    end
  end

  @spec group_keys(String.t(), String.t() | nil, module()) :: [
          {String.t(), String.t(), String.t(), String.t()}
        ]
  def group_keys(capsule_id, version_id, repo \\ Repo) when is_binary(capsule_id) do
    Attempt
    |> where([attempt], attempt.capsule_id == ^capsule_id)
    |> maybe_filter_version(version_id)
    |> select([attempt], {
      attempt.capsule_id,
      attempt.version_id,
      attempt.harness_id,
      fragment("coalesce(?, ?)", attempt.repeat_group_id, ^@single_repeat_group)
    })
    |> distinct(true)
    |> repo.all()
  end

  defp maybe_filter_version(query, nil), do: query

  defp maybe_filter_version(query, version_id),
    do: where(query, [attempt], attempt.version_id == ^version_id)

  defp summary_attrs(capsule_id, version_id, harness_id, repeat_group_id, attempts) do
    attempt_count = length(attempts)
    solved_attempts = Enum.filter(attempts, &effective_solved?/1)
    solve_count = length(solved_attempts)
    solve_rate = if attempt_count == 0, do: 0.0, else: solve_count / attempt_count

    %{
      "summary_id" => summary_id(capsule_id, version_id, harness_id, repeat_group_id),
      "capsule_id" => capsule_id,
      "version_id" => version_id,
      "harness_id" => harness_id,
      "repeat_group_id" => repeat_group_id,
      "attempt_count" => attempt_count,
      "solve_count" => solve_count,
      "solve_rate" => solve_rate,
      "reliable" => attempt_count >= 5 and solve_count >= 4,
      "brittle" => attempt_count >= 5 and solve_count in [1, 2],
      "answer_variance" => answer_variance(attempts),
      "median_runtime_seconds" => median_numeric(Enum.map(attempts, & &1.runtime_seconds)),
      "p90_runtime_seconds" => p90_numeric(Enum.map(attempts, & &1.runtime_seconds)),
      "median_cost_usd_micros" => median_integer(Enum.map(attempts, & &1.cost_usd_micros)),
      "validation_confirmed_count" => validation_confirmed_count(attempts),
      "last_attempt_at" => last_attempt_at(attempts)
    }
  end

  defp effective_solved?(%Attempt{} = attempt) do
    validations = attempt.validations || []

    cond do
      official_rejected?(validations) -> false
      Enum.any?(validations, &(&1.result == :confirmed)) -> true
      attempt.solved == true -> true
      true -> false
    end
  end

  defp official_rejected?(validations) do
    Enum.any?(validations, fn
      %Validation{role: :official, result: result} -> result in @official_rejection_results
      _validation -> false
    end)
  end

  defp answer_variance(attempts) do
    entries =
      attempts
      |> Enum.map(&answer_hash/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.map(fn {answer_hash, count} ->
        %{"answer_hash" => answer_hash, "count" => count}
      end)
      |> Enum.sort_by(&{-&1["count"], &1["answer_hash"]})

    %{
      "unique_answer_count" => length(entries),
      "answers" => entries
    }
  end

  defp answer_hash(%Attempt{answer_hash: answer_hash})
       when is_binary(answer_hash) and answer_hash != "",
       do: answer_hash

  defp answer_hash(%Attempt{answer_json: answer_json}) when is_map(answer_json) do
    hash_term(answer_json)
  end

  defp answer_hash(%Attempt{answer_text: answer_text})
       when is_binary(answer_text) and answer_text != "" do
    hash_term(answer_text)
  end

  defp answer_hash(_attempt), do: nil

  defp hash_term(term) do
    "sha256:" <>
      (:crypto.hash(:sha256, :erlang.term_to_binary(term))
       |> Base.encode16(case: :lower))
  end

  defp validation_confirmed_count(attempts) do
    attempts
    |> Enum.flat_map(&(&1.validations || []))
    |> Enum.count(&(&1.result == :confirmed))
  end

  defp last_attempt_at(attempts) do
    attempts
    |> Enum.map(&(&1.submitted_at || &1.inserted_at))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp median_numeric(values) do
    values
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
    |> median()
  end

  defp median_integer(values) do
    values
    |> median_numeric()
    |> case do
      nil -> nil
      value -> round(value)
    end
  end

  defp p90_numeric(values) do
    sorted =
      values
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    case sorted do
      [] ->
        nil

      [_ | _] ->
        index =
          sorted
          |> length()
          |> Kernel.*(0.9)
          |> Float.ceil()
          |> trunc()
          |> Kernel.-(1)

        Enum.at(sorted, index) * 1.0
    end
  end

  defp median([]), do: nil

  defp median(values) do
    count = length(values)
    midpoint = div(count, 2)

    if rem(count, 2) == 1 do
      Enum.at(values, midpoint) * 1.0
    else
      (Enum.at(values, midpoint - 1) + Enum.at(values, midpoint)) / 2
    end
  end

  defp summary_id(capsule_id, version_id, harness_id, repeat_group_id) do
    hash =
      :crypto.hash(:sha256, "#{capsule_id}:#{version_id}:#{harness_id}:#{repeat_group_id}")
      |> Base.encode16(case: :lower)
      |> binary_part(0, 24)

    "summary_#{hash}"
  end
end
