defmodule TechTree.Benchmarks do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias TechTree.Agents.AgentIdentity

  alias TechTree.Benchmarks.{
    Artifact,
    Attempt,
    Capsule,
    CapsuleVersion,
    Harness,
    Reliability,
    ReliabilitySummary,
    Validation
  }

  alias TechTree.Benchmarks.Presentation
  alias TechTree.Benchmarks.Importers.{BBH, ScienceTasks}
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Repo
  alias TechTree.Workers.RecomputeBenchmarkReliabilityWorker

  @recompute_unique [period: 300, keys: [:capsule_id, :version_id, :harness_id, :repeat_group_id]]
  @official_rejection_results [:rejected, :mixed, :needs_revision]
  @public_states [:approved, :published]
  @public_version_statuses [:approved, :published, :superseded]

  @spec list_capsules(map()) :: [Capsule.t()]
  def list_capsules(params \\ %{}) when is_map(params) do
    limit = TechTree.QueryHelpers.parse_limit(params, 50)

    Capsule
    |> maybe_filter_string_enum(:domain, params["domain"])
    |> maybe_filter_string(:field, params["field"])
    |> maybe_filter_string_enum(:visibility, params["visibility"])
    |> maybe_filter_string_enum(:workflow_state, params["workflow_state"] || params["status"])
    |> maybe_filter_string(:difficulty_label, params["difficulty"])
    |> order_by([capsule], desc: capsule.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec list_public_capsules(map()) :: [Capsule.t()]
  def list_public_capsules(params \\ %{}) when is_map(params) do
    limit = TechTree.QueryHelpers.parse_limit(params, 50)

    Capsule
    |> where([capsule], capsule.visibility == :public)
    |> where([capsule], capsule.workflow_state in ^@public_states)
    |> maybe_filter_string_enum(:domain, params["domain"])
    |> maybe_filter_string(:field, params["field"])
    |> maybe_filter_string_enum(:workflow_state, params["workflow_state"] || params["status"])
    |> maybe_filter_string(:difficulty_label, params["difficulty"])
    |> order_by([capsule], desc: capsule.published_at, desc: capsule.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload(:reliability_summaries)
  end

  @spec get_capsule(String.t()) :: {:ok, Capsule.t()} | {:error, :capsule_not_found}
  def get_capsule(capsule_id) when is_binary(capsule_id) do
    case Repo.get(Capsule, capsule_id) do
      %Capsule{} = capsule ->
        {:ok, Repo.preload(capsule, [:versions, :reliability_summaries, :artifacts])}

      nil ->
        {:error, :capsule_not_found}
    end
  end

  @spec get_public_capsule(String.t()) :: {:ok, Capsule.t()} | {:error, :capsule_not_found}
  def get_public_capsule(capsule_id) when is_binary(capsule_id) do
    with {:ok, %Capsule{} = capsule} <- get_capsule(capsule_id),
         true <- public_capsule?(capsule) do
      {:ok, capsule}
    else
      false -> {:error, :capsule_not_found}
      {:error, :capsule_not_found} -> {:error, :capsule_not_found}
    end
  end

  @spec get_capsule_version(String.t()) ::
          {:ok, CapsuleVersion.t()} | {:error, :capsule_version_not_found}
  def get_capsule_version(version_id) when is_binary(version_id) do
    case Repo.get(CapsuleVersion, version_id) do
      %CapsuleVersion{} = version -> {:ok, version}
      nil -> {:error, :capsule_version_not_found}
    end
  end

  @spec list_capsule_versions(String.t()) :: [CapsuleVersion.t()]
  def list_capsule_versions(capsule_id) when is_binary(capsule_id) do
    CapsuleVersion
    |> where([version], version.capsule_id == ^capsule_id)
    |> order_by([version], desc: version.inserted_at)
    |> Repo.all()
  end

  @spec list_public_capsule_versions(String.t()) :: [CapsuleVersion.t()]
  def list_public_capsule_versions(capsule_id) when is_binary(capsule_id) do
    CapsuleVersion
    |> where([version], version.capsule_id == ^capsule_id)
    |> where([version], version.version_status in ^@public_version_statuses)
    |> order_by([version], desc: version.inserted_at)
    |> Repo.all()
  end

  @spec get_harness(String.t()) :: {:ok, Harness.t()} | {:error, :harness_not_found}
  def get_harness(harness_id) when is_binary(harness_id), do: fetch_harness(harness_id)

  @spec get_attempt(String.t()) :: {:ok, Attempt.t()} | {:error, :attempt_not_found}
  def get_attempt(attempt_id) when is_binary(attempt_id), do: fetch_attempt(attempt_id)

  @spec list_attempt_validations(String.t()) :: [Validation.t()]
  def list_attempt_validations(attempt_id) when is_binary(attempt_id) do
    Validation
    |> where([validation], validation.attempt_id == ^attempt_id)
    |> order_by([validation], desc: validation.inserted_at)
    |> Repo.all()
  end

  @spec reliability_summaries(String.t()) :: [ReliabilitySummary.t()]
  def reliability_summaries(capsule_id) when is_binary(capsule_id) do
    ReliabilitySummary
    |> where([summary], summary.capsule_id == ^capsule_id)
    |> order_by([summary],
      desc: summary.reliable,
      desc: summary.solve_rate,
      desc: summary.attempt_count,
      asc: summary.harness_id
    )
    |> Repo.all()
  end

  @spec encode_capsule(Capsule.t()) :: map()
  defdelegate encode_capsule(capsule), to: Presentation

  @spec encode_capsule_version(CapsuleVersion.t()) :: map()
  defdelegate encode_capsule_version(version), to: Presentation

  @spec encode_harness(Harness.t()) :: map()
  defdelegate encode_harness(harness), to: Presentation

  @spec encode_attempt(Attempt.t()) :: map()
  defdelegate encode_attempt(attempt), to: Presentation

  @spec encode_validation(Validation.t()) :: map()
  defdelegate encode_validation(validation), to: Presentation

  @spec encode_reliability_summary(ReliabilitySummary.t()) :: map()
  defdelegate encode_reliability_summary(summary), to: Presentation

  @spec public_index_page(map()) :: map()
  defdelegate public_index_page(params), to: Presentation

  @spec public_detail_page(String.t()) :: {:ok, map()} | {:error, :capsule_not_found}
  defdelegate public_detail_page(capsule_id), to: Presentation

  @spec create_capsule(AgentIdentity.t(), map()) :: {:ok, Capsule.t()} | {:error, term()}
  def create_capsule(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> put_generated_id("capsule_id", "bench")
      |> Map.put("owner_agent_id", agent.id)
      |> Map.put("owner_wallet_address", agent.wallet_address)

    %Capsule{}
    |> Capsule.changeset(attrs)
    |> Repo.insert()
  end

  @spec create_capsule_version(AgentIdentity.t(), String.t(), map()) ::
          {:ok, CapsuleVersion.t()} | {:error, term()}
  def create_capsule_version(%AgentIdentity{} = agent, capsule_id, attrs)
      when is_binary(capsule_id) and is_map(attrs) do
    with {:ok, capsule} <- get_capsule(capsule_id),
         :ok <- ensure_capsule_owner(capsule, agent) do
      attrs =
        attrs
        |> put_generated_id("version_id", "benchv")
        |> Map.put("capsule_id", capsule.capsule_id)

      Multi.new()
      |> Multi.insert(:version, CapsuleVersion.changeset(%CapsuleVersion{}, attrs))
      |> Multi.update(:capsule, fn %{version: version} ->
        Ecto.Changeset.change(capsule, current_version_id: version.version_id)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{version: version}} -> {:ok, version}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @spec mark_capsule_review_ready(AgentIdentity.t(), String.t(), map()) ::
          {:ok, Capsule.t()} | {:error, term()}
  def mark_capsule_review_ready(%AgentIdentity{} = agent, capsule_id, attrs)
      when is_binary(capsule_id) and is_map(attrs) do
    with {:ok, capsule} <- get_capsule(capsule_id),
         :ok <- ensure_capsule_owner(capsule, agent),
         {:ok, version} <- fetch_version_for_capsule(capsule, attrs) do
      Multi.new()
      |> Multi.update(
        :capsule,
        Capsule.changeset(capsule, %{
          "workflow_state" => "review_ready",
          "visibility" => "private_review",
          "current_version_id" => version.version_id
        })
      )
      |> Multi.update(
        :version,
        CapsuleVersion.changeset(version, %{"version_status" => "review_ready"})
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{capsule: capsule}} -> {:ok, Repo.preload(capsule, [:reliability_summaries])}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @spec publish_capsule(AgentIdentity.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def publish_capsule(%AgentIdentity{} = agent, capsule_id, attrs)
      when is_binary(capsule_id) and is_map(attrs) do
    with {:ok, capsule} <- get_capsule(capsule_id),
         :ok <- ensure_capsule_owner(capsule, agent),
         {:ok, version} <- fetch_version_for_capsule(capsule, attrs),
         {:ok, _visibility} <- publication_visibility(attrs),
         {:ok, node_attrs} <- publication_node_attrs(capsule, version, attrs),
         {:ok, %Node{} = node} <- Nodes.create_agent_node(agent, node_attrs),
         {:ok, result} <- mark_capsule_published(capsule, version, node, attrs) do
      {:ok, Map.put(result, :publication_node, publication_node_payload(node))}
    end
  end

  @spec create_harness(AgentIdentity.t(), map()) :: {:ok, Harness.t()} | {:error, term()}
  def create_harness(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> put_generated_id("harness_id", "harness")
      |> Map.put("owner_agent_id", agent.id)

    %Harness{}
    |> Harness.changeset(attrs)
    |> Repo.insert()
  end

  @spec create_attempt(AgentIdentity.t(), map()) :: {:ok, Attempt.t()} | {:error, term()}
  def create_attempt(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    with {:ok, attrs} <- prepare_attempt_attrs(agent, attrs) do
      Multi.new()
      |> Multi.insert(:attempt, Attempt.changeset(%Attempt{}, attrs))
      |> Oban.insert(:recompute, fn %{attempt: attempt} -> recompute_job(attempt) end)
      |> Repo.transaction()
      |> case do
        {:ok, %{attempt: attempt}} -> {:ok, attempt}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @spec create_repeat_group(AgentIdentity.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_repeat_group(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    with {:ok, attempt_inputs} <- repeat_attempt_inputs(attrs) do
      repeat_group_id = normalized_repeat_group_id(attrs)

      attempt_inputs
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {attempt_attrs, index}, {:ok, prepared} ->
        attrs =
          attempt_attrs
          |> Map.put("version_id", attrs["version_id"])
          |> Map.put("harness_id", attrs["harness_id"])
          |> Map.put("repeat_group_id", repeat_group_id)
          |> Map.put_new("attempt_ordinal", index)

        case prepare_attempt_attrs(agent, attrs) do
          {:ok, prepared_attrs} -> {:cont, {:ok, prepared ++ [prepared_attrs]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, prepared_attempts} ->
          prepared_attempts
          |> Enum.with_index(1)
          |> Enum.reduce(Multi.new(), fn {attempt_attrs, index}, multi ->
            multi
            |> Multi.insert({:attempt, index}, Attempt.changeset(%Attempt{}, attempt_attrs))
            |> Oban.insert({:recompute, index}, fn changes ->
              changes
              |> Map.fetch!({:attempt, index})
              |> recompute_job()
            end)
          end)
          |> Repo.transaction()
          |> case do
            {:ok, changes} ->
              attempts =
                1..length(prepared_attempts)
                |> Enum.map(&Map.fetch!(changes, {:attempt, &1}))

              {:ok, %{repeat_group_id: repeat_group_id, attempts: attempts}}

            {:error, _step, reason, _changes} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec create_import(AgentIdentity.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_import(%AgentIdentity{}, attrs) when is_map(attrs) do
    dry_run? = Map.get(attrs, "dry_run") == true

    case Map.get(attrs, "domain") do
      "bbh" ->
        with {:ok, counts} <- BBH.backfill_all(dry_run: dry_run?) do
          {:ok, %{domain: "bbh", dry_run: dry_run?, counts: counts}}
        end

      "science_task" ->
        with {:ok, counts} <- ScienceTasks.backfill_all(dry_run: dry_run?) do
          {:ok, %{domain: "science_task", dry_run: dry_run?, counts: counts}}
        end

      _ ->
        {:error, :benchmark_import_domain_required}
    end
  end

  @spec create_validation(AgentIdentity.t(), map()) :: {:ok, Validation.t()} | {:error, term()}
  def create_validation(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    with {:ok, attempt} <- fetch_attempt_from_attrs(attrs),
         :ok <- ensure_validation_capsule_matches_attempt(attrs, attempt) do
      attrs =
        attrs
        |> put_generated_id("validation_id", "validation")
        |> Map.put("attempt_id", attempt.attempt_id)
        |> Map.put("capsule_id", attempt.capsule_id)
        |> Map.put("validator_agent_id", agent.id)
        |> Map.put("validator_wallet_address", agent.wallet_address)

      Multi.new()
      |> Multi.insert(:validation, Validation.changeset(%Validation{}, attrs))
      |> Multi.run(:attempt, fn repo, %{validation: validation} ->
        update_attempt_after_validation(repo, attempt, validation)
      end)
      |> Oban.insert(:recompute, fn %{attempt: attempt} -> recompute_job(attempt) end)
      |> Repo.transaction()
      |> case do
        {:ok, %{validation: validation}} -> {:ok, validation}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @spec create_artifact(AgentIdentity.t(), map()) :: {:ok, Artifact.t()} | {:error, term()}
  def create_artifact(%AgentIdentity{}, attrs) when is_map(attrs) do
    attrs = put_generated_id(attrs, "artifact_id", "artifact")

    %Artifact{}
    |> Artifact.changeset(attrs)
    |> Repo.insert()
  end

  @spec recompute_reliability(String.t(), String.t() | nil) ::
          {:ok, [ReliabilitySummary.t()]} | {:error, term()}
  def recompute_reliability(capsule_id, version_id \\ nil) when is_binary(capsule_id) do
    capsule_id
    |> Reliability.group_keys(version_id)
    |> Enum.reduce_while({:ok, []}, fn {capsule_id, version_id, harness_id, repeat_group_id},
                                       {:ok, summaries} ->
      case Reliability.recompute_group(capsule_id, version_id, harness_id, repeat_group_id) do
        {:ok, nil} -> {:cont, {:ok, summaries}}
        {:ok, summary} -> {:cont, {:ok, [summary | summaries]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, summaries} -> {:ok, Enum.reverse(summaries)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec recompute_reliability_group(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, ReliabilitySummary.t() | nil} | {:error, term()}
  def recompute_reliability_group(capsule_id, version_id, harness_id, repeat_group_id)
      when is_binary(capsule_id) and is_binary(version_id) and is_binary(harness_id) and
             is_binary(repeat_group_id) do
    Reliability.recompute_group(capsule_id, version_id, harness_id, repeat_group_id)
  end

  @spec sync_publication_anchor!(integer() | String.t(), map()) :: :ok
  def sync_publication_anchor!(node_id, attrs) when is_map(attrs) do
    normalized_node_id = normalize_node_id(node_id)
    tx_hash = Map.get(attrs, :tx_hash) || Map.get(attrs, "tx_hash")
    chain_id = Map.get(attrs, :chain_id) || Map.get(attrs, "chain_id")

    if normalized_node_id && is_binary(tx_hash) && is_integer(chain_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      CapsuleVersion
      |> where([version], version.publication_node_id == ^normalized_node_id)
      |> Repo.update_all(
        set: [
          chain_tx_hash: tx_hash,
          chain_id: chain_id,
          anchored_at: now,
          updated_at: now
        ]
      )
    end

    :ok
  end

  @spec scoreboard(String.t(), map()) :: map()
  def scoreboard(capsule_id, params \\ %{}) when is_binary(capsule_id) and is_map(params) do
    limit = TechTree.QueryHelpers.parse_limit(params, 25)

    entries =
      ReliabilitySummary
      |> where([summary], summary.capsule_id == ^capsule_id)
      |> maybe_filter_string(:version_id, params["version_id"])
      |> order_by([summary],
        desc: summary.reliable,
        desc: summary.solve_rate,
        desc: summary.solve_count,
        asc: summary.harness_id
      )
      |> limit(^limit)
      |> Repo.all()

    %{
      capsule_id: capsule_id,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      entries: entries
    }
  end

  defp fetch_version_for_capsule(%Capsule{} = capsule, attrs) do
    version_id = required_attr(attrs, "version_id")

    cond do
      is_nil(version_id) ->
        {:error, :version_id_required}

      true ->
        with {:ok, version} <- get_capsule_version(version_id),
             :ok <- ensure_version_belongs_to_capsule(version, capsule) do
          {:ok, version}
        end
    end
  end

  defp ensure_version_belongs_to_capsule(
         %CapsuleVersion{capsule_id: capsule_id},
         %Capsule{capsule_id: capsule_id}
       ),
       do: :ok

  defp ensure_version_belongs_to_capsule(%CapsuleVersion{}, %Capsule{}),
    do: {:error, :capsule_version_mismatch}

  defp publication_node_attrs(%Capsule{} = capsule, %CapsuleVersion{} = version, attrs) do
    with {:ok, seed} <- required_text(attrs, "seed", :seed_required),
         {:ok, parent_id} <- required_positive_integer(attrs, "parent_id", :parent_id_required),
         {:ok, notebook_source} <-
           required_text(attrs, "notebook_source", :notebook_source_required) do
      {:ok,
       %{
         "seed" => seed,
         "kind" => "data",
         "title" => Map.get(attrs, "title") || capsule.title,
         "summary" => Map.get(attrs, "summary") || capsule.summary_md,
         "parent_id" => parent_id,
         "notebook_source" => notebook_source,
         "idempotency_key" =>
           Map.get(attrs, "idempotency_key") ||
             "benchmark:publish:#{capsule.capsule_id}:#{version.version_id}",
         "paid_payload" => Map.get(attrs, "paid_payload")
       }}
    end
  end

  defp mark_capsule_published(capsule, version, node, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    with {:ok, visibility} <- publication_visibility(attrs) do
      Multi.new()
      |> Multi.update(
        :capsule,
        Capsule.changeset(capsule, %{
          "source_node_id" => node.id,
          "workflow_state" => "published",
          "visibility" => visibility,
          "current_version_id" => version.version_id,
          "published_at" => now
        })
      )
      |> Multi.update(
        :version,
        CapsuleVersion.changeset(version, %{
          "version_status" => "published",
          "publication_node_id" => node.id,
          "manifest_cid" => node.manifest_cid,
          "manifest_uri" => node.manifest_uri,
          "manifest_sha256" => node.manifest_hash,
          "chain_tx_hash" => node.tx_hash,
          "chain_id" => node.chain_id,
          "anchored_at" => if(node.status == :anchored, do: now)
        })
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{capsule: capsule, version: version}} ->
          {:ok, %{capsule: capsule, version: version}}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  defp publication_visibility(attrs) do
    case Map.get(attrs, "visibility") || "public" do
      visibility when visibility in ["public", "paid_access"] -> {:ok, visibility}
      _other -> {:error, :publication_visibility_invalid}
    end
  end

  defp publication_node_payload(%Node{} = node) do
    publish_attempt = Nodes.get_publish_attempt(node.publish_idempotency_key)

    %{
      node_id: node.id,
      manifest_cid: node.manifest_cid,
      status: Atom.to_string(node.status),
      publish_status: publish_status(publish_attempt, node),
      anchor_status: anchor_status(node.status)
    }
  end

  defp publish_status(%{status: status}, _node) when is_binary(status), do: status
  defp publish_status(_attempt, %Node{status: status}), do: Atom.to_string(status)

  defp anchor_status(:anchored), do: "anchored"
  defp anchor_status(:failed_anchor), do: "failed_anchor"
  defp anchor_status(_status), do: "pending"

  defp prepare_attempt_attrs(%AgentIdentity{} = agent, attrs) when is_map(attrs) do
    with {:ok, version} <- fetch_version_from_attrs(attrs),
         {:ok, _capsule} <- get_capsule(version.capsule_id),
         :ok <- ensure_version_accepts_attempts(version),
         {:ok, harness} <- fetch_harness_from_attrs(attrs),
         :ok <- ensure_attempt_capsule_matches_version(attrs, version),
         :ok <- ensure_input_bundle_matches_version(attrs, version),
         :ok <- ensure_harness_bundle_matches_attempt(attrs, harness) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      attrs =
        attrs
        |> put_generated_id("attempt_id", "attempt")
        |> Map.put("capsule_id", version.capsule_id)
        |> Map.put("version_id", version.version_id)
        |> Map.put("harness_id", harness.harness_id)
        |> put_default_repeat_group()
        |> Map.put("solver_agent_id", agent.id)
        |> Map.put("solver_wallet_address", agent.wallet_address)
        |> Map.put_new("submitted_at", now)

      {:ok, attrs}
    end
  end

  defp repeat_attempt_inputs(%{"attempts" => attempts}) when is_list(attempts) do
    attempts
    |> Enum.reject(&(&1 == %{}))
    |> case do
      [] -> {:error, :repeat_attempts_required}
      prepared -> {:ok, prepared}
    end
  end

  defp repeat_attempt_inputs(_attrs), do: {:error, :repeat_attempts_required}

  defp normalized_repeat_group_id(attrs) do
    case required_attr(attrs, "repeat_group_id") do
      nil -> generated_id("repeat")
      repeat_group_id -> repeat_group_id
    end
  end

  defp required_text(attrs, field, error) do
    case required_attr(attrs, field) do
      nil -> {:error, error}
      value -> {:ok, value}
    end
  end

  defp required_positive_integer(attrs, field, error) do
    case Map.get(attrs, field) do
      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed, ""} when parsed > 0 -> {:ok, parsed}
          _ -> {:error, error}
        end

      _ ->
        {:error, error}
    end
  end

  defp normalize_node_id(value) when is_integer(value) and value > 0, do: value

  defp normalize_node_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp normalize_node_id(_value), do: nil

  defp fetch_harness(harness_id) do
    case Repo.get(Harness, harness_id) do
      %Harness{} = harness -> {:ok, harness}
      nil -> {:error, :harness_not_found}
    end
  end

  defp fetch_harness_from_attrs(attrs) do
    case required_attr(attrs, "harness_id") do
      nil -> {:error, :harness_id_required}
      harness_id -> fetch_harness(harness_id)
    end
  end

  defp fetch_attempt(attempt_id) do
    case Repo.get(Attempt, attempt_id) do
      %Attempt{} = attempt -> {:ok, attempt}
      nil -> {:error, :attempt_not_found}
    end
  end

  defp fetch_attempt_from_attrs(attrs) do
    case required_attr(attrs, "attempt_id") do
      nil -> {:error, :attempt_id_required}
      attempt_id -> fetch_attempt(attempt_id)
    end
  end

  defp fetch_version_from_attrs(attrs) do
    case required_attr(attrs, "version_id") do
      nil -> {:error, :version_id_required}
      version_id -> get_capsule_version(version_id)
    end
  end

  defp ensure_capsule_owner(%Capsule{owner_agent_id: agent_id}, %AgentIdentity{id: agent_id}),
    do: :ok

  defp ensure_capsule_owner(%Capsule{}, %AgentIdentity{}), do: {:error, :capsule_owner_required}

  defp ensure_version_accepts_attempts(%CapsuleVersion{version_status: :retired}),
    do: {:error, :capsule_version_retired}

  defp ensure_version_accepts_attempts(%CapsuleVersion{}), do: :ok

  defp ensure_attempt_capsule_matches_version(attrs, version) do
    case Map.get(attrs, "capsule_id") do
      nil -> :ok
      capsule_id when capsule_id == version.capsule_id -> :ok
      _other -> {:error, :capsule_version_mismatch}
    end
  end

  defp ensure_input_bundle_matches_version(attrs, version) do
    workspace_source = Map.get(attrs, "workspace_source") || %{}
    submitted_hash = Map.get(workspace_source, "input_bundle_sha256")

    if present?(submitted_hash) and present?(version.input_bundle_sha256) and
         submitted_hash != version.input_bundle_sha256 do
      {:error, :input_bundle_sha256_mismatch}
    else
      :ok
    end
  end

  defp ensure_harness_bundle_matches_attempt(attrs, harness) do
    run_source = Map.get(attrs, "run_source") || %{}
    submitted_hash = Map.get(run_source, "harness_bundle_hash")

    if present?(submitted_hash) and submitted_hash != harness.normalized_bundle_hash do
      {:error, :harness_bundle_hash_mismatch}
    else
      :ok
    end
  end

  defp ensure_validation_capsule_matches_attempt(attrs, attempt) do
    case Map.get(attrs, "capsule_id") do
      nil -> :ok
      capsule_id when capsule_id == attempt.capsule_id -> :ok
      _other -> {:error, :attempt_capsule_mismatch}
    end
  end

  defp update_attempt_after_validation(repo, attempt, validation) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    attrs =
      if official_rejected_after_validation?(repo, attempt, validation) do
        %{status: :rejected, score_status: :rejected, solved: false, validated_at: now}
      else
        attempt_attrs_for_validation(validation, now)
      end

    attempt
    |> Ecto.Changeset.change(attrs)
    |> repo.update()
  end

  defp official_rejected_after_validation?(_repo, _attempt, %Validation{
         role: :official,
         result: result
       })
       when result in @official_rejection_results,
       do: true

  defp official_rejected_after_validation?(repo, attempt, _validation) do
    Validation
    |> where([validation], validation.attempt_id == ^attempt.attempt_id)
    |> where([validation], validation.role == :official)
    |> where([validation], validation.result in ^@official_rejection_results)
    |> repo.exists?()
  end

  defp attempt_attrs_for_validation(%Validation{result: :confirmed}, now) do
    %{status: :validated, score_status: :scored, solved: true, validated_at: now}
  end

  defp attempt_attrs_for_validation(%Validation{role: :official}, now) do
    %{status: :rejected, score_status: :rejected, solved: false, validated_at: now}
  end

  defp attempt_attrs_for_validation(%Validation{}, now) do
    %{status: :validation_pending, validated_at: now}
  end

  defp recompute_job(%Attempt{} = attempt) do
    RecomputeBenchmarkReliabilityWorker.new(
      %{
        "capsule_id" => attempt.capsule_id,
        "version_id" => attempt.version_id,
        "harness_id" => attempt.harness_id,
        "repeat_group_id" => attempt.repeat_group_id || Reliability.single_repeat_group()
      },
      unique: @recompute_unique
    )
  end

  defp put_generated_id(attrs, field, prefix) do
    case Map.get(attrs, field) do
      value when is_binary(value) and value != "" -> attrs
      _value -> Map.put(attrs, field, generated_id(prefix))
    end
  end

  defp generated_id(prefix) do
    suffix =
      :crypto.strong_rand_bytes(12)
      |> Base.url_encode64(padding: false)

    "#{prefix}_#{suffix}"
  end

  defp put_default_repeat_group(attrs) do
    case Map.get(attrs, "repeat_group_id") do
      value when is_binary(value) and value != "" ->
        attrs

      _value ->
        Map.put(attrs, "repeat_group_id", "attempt:#{Map.fetch!(attrs, "attempt_id")}")
    end
  end

  defp required_attr(attrs, field) do
    case Map.get(attrs, field) do
      value when is_binary(value) and value != "" -> value
      _value -> nil
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp maybe_filter_string(query, _field, nil), do: query
  defp maybe_filter_string(query, _field, ""), do: query

  defp maybe_filter_string(query, field, value) when is_binary(value) do
    where(query, [record], field(record, ^field) == ^value)
  end

  defp maybe_filter_string_enum(query, _field, nil), do: query
  defp maybe_filter_string_enum(query, _field, ""), do: query

  defp maybe_filter_string_enum(query, field, value) when is_binary(value) do
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

  defp public_capsule?(%Capsule{visibility: :public, workflow_state: state})
       when state in @public_states,
       do: true

  defp public_capsule?(%Capsule{}), do: false
end
