defmodule TechTree.Benchmarks.Presentation do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Benchmarks.{
    Artifact,
    Attempt,
    Capsule,
    CapsuleVersion,
    Harness,
    ReliabilitySummary,
    Validation
  }

  alias TechTree.Repo

  @public_states [:approved, :published]
  @public_version_statuses [:approved, :published, :superseded]
  @public_artifact_visibilities [:public]
  @domain_filters [
    {"all", "All"},
    {"bbh", "BBH"},
    {"science_task", "Science"},
    {"bioinformatics", "Bioinformatics"},
    {"agent_skill", "Agent Skills"}
  ]

  @spec public_index_page(map()) :: map()
  def public_index_page(params) when is_map(params) do
    filters = %{
      domain: blank_to_nil(params["domain"]),
      field: blank_to_nil(params["field"]),
      status: blank_to_nil(params["status"]),
      difficulty: blank_to_nil(params["difficulty"])
    }

    capsules =
      Capsule
      |> where([capsule], capsule.visibility == :public)
      |> where([capsule], capsule.workflow_state in ^@public_states)
      |> maybe_filter_enum(:domain, filters.domain)
      |> maybe_filter_string(:field, filters.field)
      |> maybe_filter_enum(:workflow_state, filters.status)
      |> maybe_filter_string(:difficulty_label, filters.difficulty)
      |> order_by([capsule], desc: capsule.published_at, desc: capsule.inserted_at)
      |> limit(100)
      |> Repo.all()
      |> Repo.preload(:reliability_summaries)

    cards = Enum.map(capsules, &capsule_card/1)

    %{
      filters: filters,
      capsules: cards,
      domains: @domain_filters,
      fields: filter_values(cards, :field),
      statuses: filter_values(cards, :workflow_state),
      difficulties: filter_values(cards, :difficulty_label),
      counts_by_domain: counts_by(cards, :domain)
    }
  end

  @spec public_detail_page(String.t()) :: {:ok, map()} | {:error, :capsule_not_found}
  def public_detail_page(capsule_id) when is_binary(capsule_id) do
    case fetch_public_capsule(capsule_id) do
      nil ->
        {:error, :capsule_not_found}

      %Capsule{} = capsule ->
        capsule = Repo.preload(capsule, [:reliability_summaries])
        {:ok, capsule_detail(capsule)}
    end
  end

  @spec encode_capsule(Capsule.t()) :: map()
  def encode_capsule(%Capsule{} = capsule) do
    capsule
    |> base_capsule_map()
    |> maybe_put(
      :reliability,
      capsule |> loaded_list(:reliability_summaries) |> best_reliability() |> encode_or_nil()
    )
  end

  @spec encode_capsule_version(CapsuleVersion.t()) :: map()
  def encode_capsule_version(%CapsuleVersion{} = version) do
    %{
      version_id: version.version_id,
      capsule_id: version.capsule_id,
      version_label: version.version_label,
      version_status: atom_string(version.version_status),
      manifest_cid: version.manifest_cid,
      manifest_sha256: version.manifest_sha256,
      manifest_uri: version.manifest_uri,
      input_bundle_cid: version.input_bundle_cid,
      input_bundle_sha256: version.input_bundle_sha256,
      validation_notebook_cid: version.validation_notebook_cid,
      validation_notebook_sha256: version.validation_notebook_sha256,
      redacted_validation_notebook_cid: version.redacted_validation_notebook_cid,
      ground_truth_manifest_hash: version.ground_truth_manifest_hash,
      ground_truth_storage_policy: version.ground_truth_storage_policy || %{},
      environment_lock_ref: version.environment_lock_ref || %{},
      data_manifest: version.data_manifest || %{},
      capsule_source: version.capsule_source || %{},
      publication_node_id: version.publication_node_id,
      chain_tx_hash: version.chain_tx_hash,
      chain_id: version.chain_id,
      anchored_at: version.anchored_at,
      inserted_at: version.inserted_at,
      updated_at: version.updated_at
    }
  end

  @spec encode_harness(Harness.t()) :: map()
  def encode_harness(%Harness{} = harness) do
    %{
      harness_id: harness.harness_id,
      name: harness.name,
      description_md: harness.description_md,
      domain: harness.domain,
      runner_kind: atom_string(harness.runner_kind),
      model_id: harness.model_id,
      agent_runtime: harness.agent_runtime,
      harness_version: harness.harness_version,
      prompt_pack_ref: harness.prompt_pack_ref || %{},
      skill_pack_refs: harness.skill_pack_refs || [],
      tool_profile: harness.tool_profile || %{},
      runtime_image: harness.runtime_image,
      dependency_lock_ref: harness.dependency_lock_ref || %{},
      workspace_policy: harness.workspace_policy || %{},
      normalized_bundle_hash: harness.normalized_bundle_hash,
      source: harness.source || %{},
      inserted_at: harness.inserted_at,
      updated_at: harness.updated_at
    }
  end

  @spec encode_attempt(Attempt.t()) :: map()
  def encode_attempt(%Attempt{} = attempt) do
    %{
      attempt_id: attempt.attempt_id,
      capsule_id: attempt.capsule_id,
      version_id: attempt.version_id,
      harness_id: attempt.harness_id,
      solver_wallet_address: attempt.solver_wallet_address,
      repeat_group_id: attempt.repeat_group_id,
      attempt_ordinal: attempt.attempt_ordinal,
      status: atom_string(attempt.status),
      score_status: atom_string(attempt.score_status),
      raw_score: attempt.raw_score,
      normalized_score: attempt.normalized_score,
      score_source: attempt.score_source,
      solved: attempt.solved,
      answer_text: attempt.answer_text,
      answer_json: attempt.answer_json,
      answer_hash: attempt.answer_hash,
      verdict_json: attempt.verdict_json || %{},
      run_bundle_cid: attempt.run_bundle_cid,
      run_bundle_sha256: attempt.run_bundle_sha256,
      solver_notebook_cid: attempt.solver_notebook_cid,
      report_cid: attempt.report_cid,
      tool_calls_cid: attempt.tool_calls_cid,
      log_cid: attempt.log_cid,
      artifact_manifest: attempt.artifact_manifest || %{},
      runtime_seconds: attempt.runtime_seconds,
      cost_usd_micros: attempt.cost_usd_micros,
      tokens_input: attempt.tokens_input,
      tokens_output: attempt.tokens_output,
      tool_install_events_count: attempt.tool_install_events_count,
      external_resource_call_count: attempt.external_resource_call_count,
      run_source: attempt.run_source || %{},
      workspace_source: attempt.workspace_source || %{},
      submitted_at: attempt.submitted_at,
      validated_at: attempt.validated_at,
      inserted_at: attempt.inserted_at,
      updated_at: attempt.updated_at
    }
  end

  @spec encode_validation(Validation.t()) :: map()
  def encode_validation(%Validation{} = validation) do
    %{
      validation_id: validation.validation_id,
      attempt_id: validation.attempt_id,
      capsule_id: validation.capsule_id,
      validator_wallet_address: validation.validator_wallet_address,
      role: atom_string(validation.role),
      method: atom_string(validation.method),
      result: atom_string(validation.result),
      reproduced_raw_score: validation.reproduced_raw_score,
      reproduced_normalized_score: validation.reproduced_normalized_score,
      tolerance_raw_abs: validation.tolerance_raw_abs,
      summary_md: validation.summary_md,
      validation_notebook_cid: validation.validation_notebook_cid,
      verdict_json: validation.verdict_json || %{},
      review_source: validation.review_source || %{},
      review_node_id: validation.review_node_id,
      chain_tx_hash: validation.chain_tx_hash,
      chain_id: validation.chain_id,
      inserted_at: validation.inserted_at,
      updated_at: validation.updated_at
    }
  end

  @spec encode_reliability_summary(ReliabilitySummary.t()) :: map()
  def encode_reliability_summary(%ReliabilitySummary{} = summary) do
    %{
      summary_id: summary.summary_id,
      capsule_id: summary.capsule_id,
      version_id: summary.version_id,
      harness_id: summary.harness_id,
      repeat_group_id: summary.repeat_group_id,
      attempt_count: summary.attempt_count,
      solve_count: summary.solve_count,
      solve_rate: summary.solve_rate,
      reliable: summary.reliable,
      brittle: summary.brittle,
      answer_variance: summary.answer_variance || %{},
      median_runtime_seconds: summary.median_runtime_seconds,
      p90_runtime_seconds: summary.p90_runtime_seconds,
      median_cost_usd_micros: summary.median_cost_usd_micros,
      validation_confirmed_count: summary.validation_confirmed_count,
      last_attempt_at: summary.last_attempt_at,
      inserted_at: summary.inserted_at,
      updated_at: summary.updated_at
    }
  end

  defp fetch_public_capsule(capsule_id) do
    Capsule
    |> where([capsule], capsule.capsule_id == ^capsule_id)
    |> where([capsule], capsule.visibility == :public)
    |> where([capsule], capsule.workflow_state in ^@public_states)
    |> Repo.one()
  end

  defp capsule_detail(%Capsule{} = capsule) do
    reliability =
      capsule |> loaded_list(:reliability_summaries) |> Enum.map(&encode_reliability_summary/1)

    versions = capsule |> public_versions() |> Enum.map(&encode_capsule_version/1)

    %{
      capsule: encode_capsule(capsule),
      versions: versions,
      reliability: reliability,
      scoreboard: %{
        capsule_id: capsule.capsule_id,
        entries: reliability
      },
      artifacts: capsule |> public_artifacts() |> Enum.map(&encode_artifact/1),
      cards: detail_cards(capsule, reliability)
    }
  end

  defp capsule_card(%Capsule{} = capsule) do
    encoded = encode_capsule(capsule)
    reliability = best_reliability(loaded_list(capsule, :reliability_summaries))

    Map.merge(encoded, %{
      href: "/benchmarks/#{capsule.capsule_id}",
      field_label: capsule.field || "General",
      difficulty_label: capsule.difficulty_label || "Unlabeled",
      reliability_label: reliability_label(reliability),
      attempt_label: attempt_label(reliability)
    })
  end

  defp base_capsule_map(%Capsule{} = capsule) do
    %{
      capsule_id: capsule.capsule_id,
      source_node_id: capsule.source_node_id,
      owner_wallet_address: capsule.owner_wallet_address,
      domain: atom_string(capsule.domain),
      field: capsule.field,
      family_ref: capsule.family_ref,
      provider: capsule.provider,
      provider_ref: capsule.provider_ref,
      title: capsule.title,
      summary_md: capsule.summary_md,
      question_md: capsule.question_md,
      difficulty_label: capsule.difficulty_label,
      human_baseline_status: atom_string(capsule.human_baseline_status),
      ground_truth_policy: atom_string(capsule.ground_truth_policy),
      answer_format: capsule.answer_format || %{},
      allowed_tools_policy: capsule.allowed_tools_policy || %{},
      external_resource_policy: capsule.external_resource_policy || %{},
      scoring_policy: capsule.scoring_policy || %{},
      anti_cheat_policy: capsule.anti_cheat_policy || %{},
      workflow_state: atom_string(capsule.workflow_state),
      visibility: atom_string(capsule.visibility),
      current_version_id: capsule.current_version_id,
      published_at: capsule.published_at,
      retired_at: capsule.retired_at,
      inserted_at: capsule.inserted_at,
      updated_at: capsule.updated_at
    }
  end

  defp detail_cards(capsule, reliability) do
    [
      %{
        id: "policy",
        title: "Answer policy",
        value: capsule.ground_truth_policy |> atom_string() |> labelize()
      },
      %{
        id: "attempts",
        title: "Attempts",
        value: reliability |> total_attempts() |> Integer.to_string()
      },
      %{
        id: "reviews",
        title: "Confirmed reviews",
        value: reliability |> total_confirmations() |> Integer.to_string()
      }
    ]
  end

  defp encode_artifact(artifact) do
    %{
      artifact_id: artifact.artifact_id,
      capsule_id: artifact.capsule_id,
      version_id: artifact.version_id,
      attempt_id: artifact.attempt_id,
      validation_id: artifact.validation_id,
      kind: atom_string(artifact.kind),
      name: artifact.name,
      cid: artifact.cid,
      uri: artifact.uri,
      sha256: artifact.sha256,
      byte_size: artifact.byte_size,
      content_type: artifact.content_type,
      storage_provider: artifact.storage_provider,
      visibility: atom_string(artifact.visibility),
      encryption_meta: artifact.encryption_meta || %{},
      license: artifact.license
    }
  end

  defp best_reliability(summaries) do
    summaries
    |> Enum.sort_by(fn summary ->
      {summary.reliable, summary.solve_rate || 0.0, summary.attempt_count || 0}
    end)
    |> List.last()
  end

  defp reliability_label(nil), do: "No attempts yet"

  defp reliability_label(%ReliabilitySummary{solve_rate: solve_rate, reliable: true}) do
    "#{percent(solve_rate)} reliable"
  end

  defp reliability_label(%ReliabilitySummary{solve_rate: solve_rate, brittle: true}) do
    "#{percent(solve_rate)} brittle"
  end

  defp reliability_label(%ReliabilitySummary{solve_rate: solve_rate}),
    do: "#{percent(solve_rate)} solve rate"

  defp attempt_label(nil), do: "0 attempts"
  defp attempt_label(%ReliabilitySummary{attempt_count: 1}), do: "1 attempt"
  defp attempt_label(%ReliabilitySummary{attempt_count: count}), do: "#{count} attempts"

  defp percent(nil), do: "0%"
  defp percent(value), do: "#{round(value * 100)}%"

  defp total_attempts(reliability), do: Enum.reduce(reliability, 0, &(&1.attempt_count + &2))

  defp total_confirmations(reliability),
    do: Enum.reduce(reliability, 0, &(&1.validation_confirmed_count + &2))

  defp filter_values(cards, key) do
    cards
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp counts_by(cards, key) do
    Enum.frequencies_by(cards, &Map.get(&1, key))
  end

  defp encode_or_nil(nil), do: nil
  defp encode_or_nil(summary), do: encode_reliability_summary(summary)

  defp loaded_list(struct, key) do
    case Map.fetch!(struct, key) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      list when is_list(list) -> list
    end
  end

  defp public_versions(%Capsule{capsule_id: capsule_id}) do
    CapsuleVersion
    |> where([version], version.capsule_id == ^capsule_id)
    |> where([version], version.version_status in ^@public_version_statuses)
    |> order_by([version], desc: version.inserted_at)
    |> Repo.all()
  end

  defp public_artifacts(%Capsule{capsule_id: capsule_id}) do
    Artifact
    |> where([artifact], artifact.capsule_id == ^capsule_id)
    |> where([artifact], artifact.visibility in ^@public_artifact_visibilities)
    |> order_by([artifact], desc: artifact.inserted_at)
    |> Repo.all()
  end

  defp maybe_filter_string(query, _field, nil), do: query

  defp maybe_filter_string(query, field, value) do
    where(query, [record], field(record, ^field) == ^value)
  end

  defp maybe_filter_enum(query, _field, nil), do: query

  defp maybe_filter_enum(query, field, value) do
    case safe_existing_atom(value) do
      {:ok, atom} -> where(query, [record], field(record, ^field) == ^atom)
      :error -> where(query, false)
    end
  end

  defp safe_existing_atom(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> :error
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp labelize(nil), do: "Unknown"

  defp labelize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp atom_string(nil), do: nil
  defp atom_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_string(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
