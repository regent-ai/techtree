defmodule TechTree.BBH.PublicReads do
  @moduledoc false

  import Ecto.Query

  alias TechTree.BBH.{
    Capsule,
    Helpers,
    Genome,
    ReviewRequest,
    ReviewSubmission,
    Run,
    Validation
  }

  alias TechTree.Repo

  @draft_split "draft"
  @challenge_split "challenge"
  @review_open_states [:open, :claimed]

  def list_runs(opts \\ %{}) do
    split = Map.get(opts, "split") || Map.get(opts, :split)
    validations_query = from validation in Validation, order_by: [desc: validation.inserted_at]

    Run
    |> maybe_filter_runs_by_split(split)
    |> order_by([run], desc: run.inserted_at)
    |> preload([:capsule, :genome, validations: ^validations_query])
    |> Repo.all()
  end

  def list_capsules(opts \\ %{}) do
    split = Map.get(opts, "split") || Map.get(opts, :split)

    Capsule
    |> maybe_filter_capsules_by_split(split)
    |> maybe_limit_capsule_inventory(split)
    |> order_by([capsule], asc: capsule.inserted_at, asc: capsule.capsule_id)
    |> Repo.all()
  end

  def list_public_capsules(opts \\ %{}) do
    split = Map.get(opts, "split") || Map.get(opts, :split)

    Capsule
    |> maybe_filter_capsules_by_split(split)
    |> order_by([capsule], asc: capsule.inserted_at, asc: capsule.capsule_id)
    |> Repo.all()
    |> Enum.filter(&public_capsule_visible?/1)
    |> Enum.map(&public_capsule_card/1)
  end

  def get_public_capsule(capsule_id) when is_binary(capsule_id) do
    case Repo.get(Capsule, capsule_id) do
      nil ->
        nil

      %Capsule{} = capsule ->
        if public_capsule_visible?(capsule), do: public_capsule_detail(capsule), else: nil
    end
  end

  def get_run(run_id) when is_binary(run_id) do
    Run
    |> Repo.get(run_id)
    |> case do
      nil ->
        nil

      run ->
        case {Repo.get(Capsule, run.capsule_id), Repo.get(Genome, run.genome_id)} do
          {%Capsule{} = capsule, %Genome{} = genome} ->
            %{
              run: run,
              capsule: capsule,
              genome: genome,
              validations: list_validations(run.run_id)
            }

          _ ->
            nil
        end
    end
  end

  def get_genome(genome_id) when is_binary(genome_id) do
    case Repo.get(Genome, genome_id) do
      nil ->
        nil

      genome ->
        %{
          genome: genome,
          runs:
            Run
            |> where([run], run.genome_id == ^genome_id)
            |> order_by([run], desc: run.inserted_at)
            |> limit(20)
            |> Repo.all()
        }
    end
  end

  def list_validations(run_id) when is_binary(run_id) do
    Validation
    |> where([validation], validation.run_id == ^run_id)
    |> order_by([validation], desc: validation.inserted_at)
    |> Repo.all()
  end

  def certificate_summary(capsule_id) when is_binary(capsule_id) do
    case Repo.get(Capsule, capsule_id) do
      nil ->
        {:error, :capsule_not_found}

      %Capsule{} = capsule ->
        if public_capsule_visible?(capsule),
          do: {:ok, certificate_summary_payload(capsule)},
          else: {:error, :capsule_not_found}
    end
  end

  def review_open_count(capsule_id) when is_binary(capsule_id) do
    ReviewRequest
    |> where(
      [request],
      request.capsule_id == ^capsule_id and request.visibility == :public_claim and
        request.state in ^@review_open_states
    )
    |> Repo.aggregate(:count, :request_id)
  end

  defp maybe_filter_runs_by_split(query, nil), do: query

  defp maybe_filter_runs_by_split(query, split) when is_binary(split) do
    where(query, [run], run.split == ^split)
  end

  defp maybe_filter_runs_by_split(query, splits) when is_list(splits) do
    where(query, [run], run.split in ^splits)
  end

  defp maybe_filter_capsules_by_split(query, nil), do: query

  defp maybe_filter_capsules_by_split(query, split) when is_binary(split) do
    where(query, [capsule], capsule.split == ^split)
  end

  defp maybe_filter_capsules_by_split(query, splits) when is_list(splits) do
    where(query, [capsule], capsule.split in ^splits)
  end

  defp maybe_limit_capsule_inventory(query, @challenge_split) do
    where(query, [capsule], not is_nil(capsule.published_at))
  end

  defp maybe_limit_capsule_inventory(query, splits) when is_list(splits) do
    if @challenge_split in splits do
      where(
        query,
        [capsule],
        capsule.split != ^@challenge_split or not is_nil(capsule.published_at)
      )
    else
      query
    end
  end

  defp maybe_limit_capsule_inventory(query, _split), do: query

  defp public_capsule_visible?(%Capsule{split: @draft_split}), do: false
  defp public_capsule_visible?(%Capsule{split: @challenge_split, published_at: nil}), do: false
  defp public_capsule_visible?(%Capsule{}), do: true

  defp public_capsule_card(%Capsule{} = capsule) do
    %{
      capsule_id: capsule.capsule_id,
      split: capsule.split,
      title: capsule.title,
      hypothesis: capsule.hypothesis,
      provider: capsule.provider,
      provider_ref: capsule.provider_ref,
      assignment_policy: capsule.assignment_policy,
      published_at: capsule.published_at,
      certificate_status: enum_value(capsule.certificate_status || :none),
      certificate_review_id: capsule.certificate_review_id,
      certificate_expires_at: capsule.certificate_expires_at,
      review_open_count: public_review_open_count(capsule.capsule_id)
    }
  end

  defp public_capsule_detail(%Capsule{} = capsule) do
    Map.merge(public_capsule_card(capsule), %{
      family_ref: capsule.family_ref,
      instance_ref: capsule.instance_ref,
      language: capsule.language,
      mode: capsule.mode,
      execution_defaults: Helpers.execution_defaults(capsule),
      task_summary: capsule.task_json,
      rubric_summary: capsule.rubric_json,
      data_manifest:
        Enum.map(capsule.data_files || [], fn file ->
          Map.take(file, ["name", "path", "sha256", "bytes"])
        end),
      artifact_source: capsule.artifact_source,
      review_open?: public_review_open_count(capsule.capsule_id) > 0
    })
  end

  defp public_review_open_count(capsule_id), do: review_open_count(capsule_id)

  defp certificate_summary_payload(%Capsule{} = capsule) do
    %{
      capsule_id: capsule.capsule_id,
      status: enum_value(capsule.certificate_status || :none),
      certificate_review_id: capsule.certificate_review_id,
      scope: capsule.certificate_scope,
      issued_at: capsule.updated_at,
      expires_at: capsule.certificate_expires_at,
      reviewer_wallet: certificate_reviewer_wallet(capsule)
    }
  end

  defp certificate_reviewer_wallet(%Capsule{certificate_review_id: nil}), do: nil

  defp certificate_reviewer_wallet(%Capsule{certificate_review_id: review_node_id}) do
    case Repo.get_by(ReviewSubmission, review_node_id: review_node_id) do
      nil -> nil
      submission -> submission.reviewer_wallet
    end
  end

  defp enum_value(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_value(value), do: value
end
