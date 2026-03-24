defmodule TechTree.V1 do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias TechTree.IPFS.LighthouseClient
  alias TechTree.Repo

  alias TechTree.V1.{
    Artifact,
    ArtifactEdge,
    Chain,
    Claim,
    CoreBridge,
    Finding,
    Node,
    NodeState,
    PayloadFile,
    RejectedIngest,
    Review,
    Run,
    Source
  }

  @manifest_files %{
    "artifact" => "artifact.manifest.json",
    "run" => "run.manifest.json",
    "review" => "review.manifest.json"
  }

  def get_node(id) when is_binary(id) do
    Node
    |> Repo.get(id)
    |> preload_node()
  end

  def get_node!(id), do: id |> get_node() || raise(Ecto.NoResultsError, queryable: Node)

  def get_artifact(id) when is_binary(id) do
    with %Node{node_type: 1} = node <- get_node(id),
         %Artifact{} = artifact <- Repo.get(Artifact, id) do
      %{
        node: node,
        artifact: artifact,
        parents: list_artifact_parents(id),
        children: list_artifact_children(id),
        runs: list_artifact_runs(id),
        claims: list_claims(id),
        sources: list_sources(id)
      }
    end
  end

  def get_run(id) when is_binary(id) do
    with %Node{node_type: 2} = node <- get_node(id),
         %Run{} = run <- Repo.get(Run, id) do
      %{
        node: node,
        run: run,
        artifact: get_artifact(run.artifact_id)
      }
    end
  end

  def get_review(id) when is_binary(id) do
    with %Node{node_type: 3} = node <- get_node(id),
         %Review{} = review <- Repo.get(Review, id) do
      %{
        node: node,
        review: review,
        target: get_node(review.target_id),
        findings: list_findings(id)
      }
    end
  end

  def list_run_reviews(id) when is_binary(id) do
    Review
    |> where([review], review.target_type == "run" and review.target_id == ^id)
    |> order_by([review], desc: review.inserted_at)
    |> Repo.all()
  end

  def list_bbh_runs(opts \\ %{}) do
    split = Map.get(opts, :split) || Map.get(opts, "split") || "eval"

    from(run in Run,
      join: node in assoc(run, :node),
      join: _artifact in Artifact,
      on: _artifact.id == run.artifact_id,
      where:
        fragment("?->'instance'->'params'->>'tree' = 'bbh'", node.manifest) and
          fragment("?->'instance'->'params'->>'split' = ?", node.manifest, ^to_string(split)),
      order_by: [desc: run.score, desc: run.inserted_at],
      preload: [node: [:state, :review]]
    )
    |> Repo.all()
  end

  def bbh_leaderboard(opts \\ %{}) do
    split = Map.get(opts, :split) || Map.get(opts, "split") || "eval"

    entries =
      list_bbh_runs(%{split: split})
      |> Enum.reduce([], fn run, acc ->
        reviews = list_run_reviews(run.id)

        official_reviews =
          Enum.filter(reviews, fn review ->
            review.kind == "validation" and review.method == "replay" and
              review.result == "confirmed"
          end)

        if official_reviews == [] do
          acc
        else
          params = get_in(run.node.manifest, ["instance", "params"]) || %{}
          genome = Map.get(params, "genome", %{})
          latest_review = List.first(official_reviews)
          score = run.score

          [
            %{
              node_id: run.id,
              artifact_id: run.artifact_id,
              fingerprint: genome["fingerprint"],
              display_name: genome["display_name"] || run.executor_id,
              score: score,
              score_label: format_score_label(score),
              review_result: latest_review.result,
              reproducible: latest_review.result == "confirmed",
              review_count: length(official_reviews),
              updated_at: latest_review.inserted_at,
              executor_harness_kind: run.executor_harness_kind,
              executor_harness_profile: run.executor_harness_profile,
              origin_kind: run.origin_kind,
              origin_transport: run.origin_transport,
              origin_session_id: run.origin_session_id
            }
            | acc
          ]
        end
      end)
      |> Enum.sort_by(fn entry -> {entry.score || -1.0, entry.updated_at} end, :desc)
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, index} -> Map.put(entry, :rank, index) end)

    %{
      tree: "bbh",
      split: split,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      entries: entries
    }
  end

  def bbh_sync_status(opts \\ %{}) do
    split = Map.get(opts, :split) || Map.get(opts, "split") || "eval"
    runs = list_bbh_runs(%{split: split})

    reviews =
      runs
      |> Enum.flat_map(&list_run_reviews(&1.id))
      |> Enum.count(fn review -> review.kind == "validation" and review.method == "replay" end)

    %{
      tree: "bbh",
      synced_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      runs: length(runs),
      reviews: reviews,
      leaderboard_entries: length(bbh_leaderboard(%{split: split}).entries)
    }
  end

  def list_artifact_parents(id) do
    ArtifactEdge
    |> where([edge], edge.child_id == ^id)
    |> order_by([edge], asc: edge.inserted_at)
    |> preload(parent: [:artifact, :run, :review, :state])
    |> Repo.all()
  end

  def list_artifact_children(id) do
    ArtifactEdge
    |> where([edge], edge.parent_id == ^id)
    |> order_by([edge], asc: edge.inserted_at)
    |> preload(child: [:artifact, :run, :review, :state])
    |> Repo.all()
  end

  def list_artifact_runs(id) do
    Run
    |> where([run], run.artifact_id == ^id)
    |> order_by([run], desc: run.inserted_at)
    |> Repo.all()
  end

  def search(term) when is_binary(term) do
    wildcard = "%#{String.trim(term)}%"

    query =
      from node in Node,
        left_join: artifact in Artifact,
        on: artifact.id == node.id,
        left_join: run in Run,
        on: run.id == node.id,
        left_join: review in Review,
        on: review.id == node.id,
        where:
          ilike(fragment("coalesce(?,'')", artifact.title), ^wildcard) or
            ilike(fragment("coalesce(?,'')", artifact.summary), ^wildcard) or
            ilike(fragment("coalesce(?,'')", run.executor_id), ^wildcard) or
            ilike(fragment("coalesce(?,'')", run.executor_harness_kind), ^wildcard) or
            ilike(fragment("coalesce(?,'')", run.executor_harness_profile), ^wildcard) or
            ilike(fragment("coalesce(?,'')", run.origin_kind), ^wildcard) or
            ilike(fragment("coalesce(?,'')", run.origin_transport), ^wildcard) or
            ilike(fragment("coalesce(?,'')", run.origin_session_id), ^wildcard) or
            ilike(fragment("coalesce(?,'')", review.result), ^wildcard) or
            ilike(fragment("coalesce(?,'')", review.method), ^wildcard)

    query
    |> Repo.all()
    |> Repo.preload([:artifact, :run, :review, :state])
  end

  def compile(node_type, path, author \\ nil) when node_type in ["artifact", "run", "review"] do
    with {:ok, payload} <- CoreBridge.compile(path, author),
         true <- payload["node_type"] == node_type do
      {:ok, payload}
    else
      false -> {:error, :node_type_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify_workspace(path, author \\ nil), do: CoreBridge.verify_workspace(path, author)

  def pin_workspace(path) do
    with {:ok, compiled} <- locate_compilation(path),
         {:ok, manifest_upload} <- upload_file(compiled.manifest_path),
         {:ok, payload_upload} <- upload_file(compiled.payload_path) do
      {:ok,
       %{
         node_id: compiled.header["id"],
         manifest_cid: manifest_upload.cid,
         payload_cid: payload_upload.cid,
         manifest_gateway_url: manifest_upload.gateway_url,
         payload_gateway_url: payload_upload.gateway_url
       }}
    end
  end

  def prepare_publish(path) do
    with {:ok, compiled} <- locate_compilation(path) do
      {:ok,
       %{
         node_id: compiled.header["id"],
         node_type: compiled.node_type,
         header: compiled.header,
         manifest: compiled.manifest,
         payload_index: compiled.payload_index
       }}
    end
  end

  def submit_publish(attrs) when is_map(attrs) do
    with {:ok, compiled} <- materialize_submission(attrs),
         {:ok, verification} <-
           CoreBridge.verify_compiled(
             compiled.node_type,
             compiled.manifest,
             compiled.payload_index,
             compiled.header
           ) do
      if verification["ok"] do
        persist_verified_node(compiled, verification)
      else
        case reject_ingest(compiled, "verification_failed") do
          {:ok, rejected} -> {:error, {:verification_failed, rejected.id}}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  def challenge_artifact(id, attrs), do: submit_typed_review(id, "artifact", "challenge", attrs)
  def challenge_run(id, attrs), do: submit_typed_review(id, "run", "challenge", attrs)
  def validate_run(id, attrs), do: submit_typed_review(id, "run", "validation", attrs)

  def ingest_published_event(attrs) do
    submit_publish(attrs)
  end

  defp submit_typed_review(id, target_type, kind, attrs) do
    with {:ok, compiled} <- materialize_submission(attrs),
         true <- compiled.node_type == "review",
         %{"target" => %{"id" => ^id, "type" => ^target_type}, "kind" => ^kind} <-
           compiled.manifest do
      submit_publish(Map.merge(attrs, compiled))
    else
      false -> {:error, :invalid_review_submission}
      nil -> {:error, :invalid_review_submission}
      {:ok, _compiled} -> {:error, :invalid_review_submission}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_review_submission}
    end
  end

  defp materialize_submission(%{"path" => path} = attrs),
    do: materialize_submission(Map.put(attrs, :path, path))

  defp materialize_submission(%{path: path} = attrs) when is_binary(path) do
    with {:ok, compiled} <- locate_compilation(path) do
      {:ok,
       %{
         node_type: compiled.node_type,
         header: compiled.header,
         manifest: compiled.manifest,
         payload_index: compiled.payload_index,
         manifest_cid: map_get(attrs, "manifest_cid", :manifest_cid),
         payload_cid: map_get(attrs, "payload_cid", :payload_cid),
         tx_hash: map_get(attrs, "tx_hash", :tx_hash),
         block_number: map_get(attrs, "block_number", :block_number),
         block_time: map_get(attrs, "block_time", :block_time)
       }}
    end
  end

  defp materialize_submission(attrs) when is_map(attrs) do
    manifest = map_get(attrs, "manifest", :manifest)
    payload_index = map_get(attrs, "payload_index", :payload_index)
    header = map_get(attrs, "header", :header)
    node_type = map_get(attrs, "node_type", :node_type) || node_type_from_header(header)
    tx_hash = map_get(attrs, "tx_hash", :tx_hash)

    cond do
      is_binary(tx_hash) ->
        fetch_chain_submission(attrs)

      is_map(manifest) and is_map(payload_index) and is_map(header) and is_binary(node_type) ->
        {:ok,
         %{
           node_type: node_type,
           manifest: manifest,
           payload_index: payload_index,
           header: header,
           manifest_cid: map_get(attrs, "manifest_cid", :manifest_cid),
           payload_cid: map_get(attrs, "payload_cid", :payload_cid),
           tx_hash: map_get(attrs, "tx_hash", :tx_hash),
           block_number: map_get(attrs, "block_number", :block_number),
           block_time: map_get(attrs, "block_time", :block_time)
         }}

      is_binary(map_get(attrs, "manifest_cid", :manifest_cid)) and
        is_binary(map_get(attrs, "payload_cid", :payload_cid)) and
        is_map(header) and is_binary(node_type) ->
        fetch_and_materialize_submission(attrs, node_type, header)

      true ->
        {:error, :invalid_submission}
    end
  end

  defp fetch_chain_submission(attrs) do
    with {:ok, chain_submission} <- Chain.fetch_published_submission(attrs),
         {:ok, manifest} <- fetch_ipfs_json(chain_submission.manifest_cid),
         {:ok, payload_index} <- fetch_payload_index(chain_submission.payload_cid) do
      {:ok,
       %{
         node_type: chain_submission.node_type,
         manifest: manifest,
         payload_index: payload_index,
         header: chain_submission.header,
         manifest_cid: chain_submission.manifest_cid,
         payload_cid: chain_submission.payload_cid,
         tx_hash: chain_submission.tx_hash,
         block_number: chain_submission.block_number,
         block_time: chain_submission.block_time
       }}
    end
  end

  defp fetch_and_materialize_submission(attrs, node_type, header) do
    manifest_cid = map_get(attrs, "manifest_cid", :manifest_cid)
    payload_cid = map_get(attrs, "payload_cid", :payload_cid)

    with {:ok, manifest} <- fetch_ipfs_json(manifest_cid),
         {:ok, payload_index} <- fetch_payload_index(payload_cid) do
      {:ok,
       %{
         node_type: node_type,
         manifest: manifest,
         payload_index: payload_index,
         header: header,
         manifest_cid: manifest_cid,
         payload_cid: payload_cid,
         tx_hash: map_get(attrs, "tx_hash", :tx_hash),
         block_number: map_get(attrs, "block_number", :block_number),
         block_time: map_get(attrs, "block_time", :block_time)
       }}
    end
  end

  defp format_score_label(score) when is_number(score) do
    :erlang.float_to_binary(score * 1.0, decimals: 2)
  end

  defp format_score_label(_score), do: "n/a"

  defp fetch_payload_index(cid) do
    case fetch_ipfs_json(cid) do
      {:ok, %{"schema_version" => "techtree.payload-index.v1"} = payload_index} ->
        {:ok, payload_index}

      _ ->
        fetch_ipfs_json(cid, "payload.index.json")
    end
  end

  defp fetch_ipfs_json(cid, suffix \\ nil) do
    path = if is_binary(suffix), do: "#{cid}/#{suffix}", else: cid

    case Req.get(url: "#{gateway_base()}/#{path}") do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        case body do
          decoded when is_map(decoded) -> {:ok, decoded}
          binary when is_binary(binary) -> Jason.decode(binary)
          _ -> {:error, :invalid_gateway_body}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:gateway_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp gateway_base do
    Application.fetch_env!(:tech_tree, TechTree.IPFS.LighthouseClient)
    |> Keyword.fetch!(:gateway_base)
  end

  defp locate_compilation(path) do
    expanded = Path.expand(path)

    dist_dir =
      if String.ends_with?(expanded, "/dist"), do: expanded, else: Path.join(expanded, "dist")

    with {:ok, payload_index} <- read_json(Path.join(dist_dir, "payload.index.json")),
         {:ok, header} <- read_json(Path.join(dist_dir, "node-header.json")),
         {:ok, node_type, manifest, manifest_path} <- locate_manifest(dist_dir) do
      {:ok,
       %{
         dist_dir: dist_dir,
         node_type: node_type,
         payload_index: payload_index,
         header: header,
         manifest: manifest,
         manifest_path: manifest_path,
         payload_path: Path.join(dist_dir, "payload.index.json")
       }}
    end
  end

  defp locate_manifest(dist_dir) do
    @manifest_files
    |> Enum.find_value(fn {node_type, filename} ->
      path = Path.join(dist_dir, filename)
      if File.exists?(path), do: {node_type, path}, else: nil
    end)
    |> case do
      {node_type, manifest_path} ->
        with {:ok, manifest} <- read_json(manifest_path) do
          {:ok, node_type, manifest, manifest_path}
        end

      nil ->
        {:error, :manifest_not_found}
    end
  end

  defp read_json(path) do
    case File.read(path) do
      {:ok, content} -> Jason.decode(content)
      {:error, reason} -> {:error, reason}
    end
  end

  defp upload_file(path) do
    {:ok, LighthouseClient.upload_path!(path)}
  rescue
    error -> {:error, {:upload_failed, Exception.message(error)}}
  end

  defp persist_verified_node(compiled, verification) do
    node_id = compiled.header["id"]
    node_type = node_type_value(compiled.node_type)

    Multi.new()
    |> Multi.delete_all(
      :delete_edges,
      from(edge in ArtifactEdge, where: edge.child_id == ^node_id or edge.parent_id == ^node_id)
    )
    |> Multi.delete_all(
      :delete_payload_files,
      from(file in PayloadFile, where: file.node_id == ^node_id)
    )
    |> Multi.delete_all(
      :delete_sources,
      from(source in Source, where: source.node_id == ^node_id)
    )
    |> Multi.delete_all(
      :delete_claims,
      from(claim in Claim, where: claim.artifact_id == ^node_id)
    )
    |> Multi.delete_all(
      :delete_findings,
      from(finding in Finding, where: finding.review_id == ^node_id)
    )
    |> Multi.delete_all(
      :delete_artifact,
      from(artifact in Artifact, where: artifact.id == ^node_id)
    )
    |> Multi.delete_all(:delete_run, from(run in Run, where: run.id == ^node_id))
    |> Multi.delete_all(:delete_review, from(review in Review, where: review.id == ^node_id))
    |> Multi.insert_or_update(
      :node,
      Node.changeset(%Node{id: node_id}, node_attrs(compiled, verification, node_type))
    )
    |> Multi.run(:type_record, fn repo, %{node: _node} ->
      insert_type_record(repo, compiled, node_id)
    end)
    |> Multi.run(:payload_files, fn repo, _changes ->
      insert_payload_files(repo, node_id, compiled.payload_index)
    end)
    |> Multi.run(:sources, fn repo, _changes ->
      insert_sources(repo, node_id, compiled.manifest)
    end)
    |> Multi.run(:claims, fn repo, _changes -> insert_claims(repo, node_id, compiled.manifest) end)
    |> Multi.run(:findings, fn repo, _changes ->
      insert_findings(repo, node_id, compiled.manifest)
    end)
    |> Multi.run(:edges, fn repo, _changes ->
      insert_edges(repo, node_id, compiled.manifest, compiled.node_type)
    end)
    |> Multi.insert_or_update(
      :node_state,
      NodeState.changeset(%NodeState{node_id: node_id}, %{
        node_id: node_id,
        validated: false,
        challenged: false,
        retired: false
      })
    )
    |> Multi.run(:review_state, fn repo, _changes -> maybe_update_target_state(repo, compiled) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{node: node}} -> {:ok, preload_node(node)}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp reject_ingest(compiled, reason) do
    %RejectedIngest{}
    |> RejectedIngest.changeset(%{
      node_id: get_in(compiled, [:header, "id"]),
      node_type: node_type_value(compiled.node_type),
      manifest_cid: compiled.manifest_cid,
      payload_cid: compiled.payload_cid,
      reason: reason,
      header: compiled.header,
      manifest: compiled.manifest,
      payload_index: compiled.payload_index
    })
    |> Repo.insert()
  end

  defp node_attrs(compiled, verification, node_type) do
    %{
      id: compiled.header["id"],
      node_type: node_type,
      author: compiled.header["author"],
      subject_id: blank_to_nil(compiled.header["subject_id"]),
      aux_id: blank_to_nil(compiled.header["aux_id"]),
      payload_hash: compiled.header["payload_hash"],
      manifest_cid: compiled.manifest_cid,
      payload_cid: compiled.payload_cid,
      schema_version: compiled.header["schema_version"],
      tx_hash: compiled.tx_hash,
      block_number: compiled.block_number,
      block_time: normalize_block_time(compiled.block_time),
      verification_status: "verified",
      verification_error: nil,
      header: verification["expected_header"] || compiled.header,
      manifest: compiled.manifest,
      payload_index: compiled.payload_index
    }
  end

  defp insert_type_record(repo, %{node_type: "artifact", manifest: manifest}, node_id) do
    %Artifact{}
    |> Artifact.changeset(%{
      id: node_id,
      kind: manifest["kind"],
      title: manifest["title"],
      summary: manifest["summary"],
      has_eval: is_map(manifest["eval"]),
      eval_mode: get_in(manifest, ["eval", "mode"])
    })
    |> repo.insert()
  end

  defp insert_type_record(repo, %{node_type: "run", manifest: manifest}, node_id) do
    metadata = run_metadata(manifest)

    %Run{}
    |> Run.changeset(%{
      id: node_id,
      artifact_id: manifest["artifact_id"],
      executor_type: get_in(manifest, ["executor", "type"]),
      executor_id: get_in(manifest, ["executor", "id"]),
      executor_harness_kind: metadata.executor_harness_kind,
      executor_harness_profile: metadata.executor_harness_profile,
      origin_kind: metadata.origin_kind,
      origin_transport: metadata.origin_transport,
      origin_session_id: metadata.origin_session_id,
      status: manifest["status"],
      score: get_in(manifest, ["metrics", "score"])
    })
    |> repo.insert()
  end

  defp insert_type_record(repo, %{node_type: "review", manifest: manifest}, node_id) do
    %Review{}
    |> Review.changeset(%{
      id: node_id,
      target_type: get_in(manifest, ["target", "type"]),
      target_id: get_in(manifest, ["target", "id"]),
      kind: manifest["kind"],
      method: manifest["method"],
      result: manifest["result"],
      scope_level: get_in(manifest, ["scope", "level"]),
      scope_path: get_in(manifest, ["scope", "path"])
    })
    |> repo.insert()
  end

  defp insert_payload_files(repo, node_id, %{"files" => files}) when is_list(files) do
    Enum.reduce_while(Enum.with_index(files), {:ok, []}, fn {file, _index}, {:ok, acc} ->
      changeset =
        PayloadFile.changeset(%PayloadFile{}, %{
          node_id: node_id,
          path: file["path"],
          sha256: file["sha256"],
          size: file["size"],
          media_type: file["media_type"],
          role: file["role"]
        })

      case repo.insert(changeset) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_payload_files(_repo, _node_id, _payload_index), do: {:ok, []}

  defp insert_sources(repo, node_id, %{"sources" => sources}) when is_list(sources) do
    Enum.reduce_while(Enum.with_index(sources, 1), {:ok, []}, fn {source, ordinal}, {:ok, acc} ->
      changeset =
        Source.changeset(%Source{}, %{
          node_id: node_id,
          ordinal: ordinal,
          kind: source["kind"],
          ref: source["ref"],
          license: source["license"],
          note: source["note"]
        })

      case repo.insert(changeset) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_sources(_repo, _node_id, _manifest), do: {:ok, []}

  defp insert_claims(repo, node_id, %{"claims" => claims}) when is_list(claims) do
    Enum.reduce_while(Enum.with_index(claims, 1), {:ok, []}, fn {claim, ordinal}, {:ok, acc} ->
      changeset =
        Claim.changeset(%Claim{}, %{
          artifact_id: node_id,
          ordinal: ordinal,
          text: claim["text"]
        })

      case repo.insert(changeset) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_claims(_repo, _node_id, _manifest), do: {:ok, []}

  defp insert_findings(repo, node_id, %{"findings" => findings}) when is_list(findings) do
    Enum.reduce_while(Enum.with_index(findings, 1), {:ok, []}, fn {finding, ordinal},
                                                                  {:ok, acc} ->
      changeset =
        Finding.changeset(%Finding{}, %{
          review_id: node_id,
          ordinal: ordinal,
          code: finding["code"],
          severity: finding["severity"],
          message: finding["message"]
        })

      case repo.insert(changeset) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_findings(_repo, _node_id, _manifest), do: {:ok, []}

  defp insert_edges(repo, node_id, %{"parents" => parents}, "artifact") when is_list(parents) do
    Enum.reduce_while(parents, {:ok, []}, fn parent, {:ok, acc} ->
      changeset =
        ArtifactEdge.changeset(%ArtifactEdge{}, %{
          child_id: node_id,
          parent_id: parent["artifact_id"],
          relation: parent["relation"],
          note: parent["note"]
        })

      case repo.insert(changeset) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_edges(_repo, _node_id, _manifest, _node_type), do: {:ok, []}

  defp maybe_update_target_state(repo, %{node_type: "review", manifest: manifest}) do
    target_id = get_in(manifest, ["target", "id"])

    state =
      Repo.get(NodeState, target_id) ||
        %NodeState{node_id: target_id, validated: false, challenged: false, retired: false}

    attrs = %{
      node_id: target_id,
      validated:
        state.validated or
          (manifest["kind"] == "validation" and manifest["result"] == "confirmed"),
      challenged:
        state.challenged or
          (manifest["kind"] == "challenge" and
             manifest["result"] in ["confirmed", "needs_revision"]),
      retired: state.retired,
      latest_review_result: manifest["result"]
    }

    state
    |> NodeState.changeset(attrs)
    |> repo.insert_or_update()
  end

  defp maybe_update_target_state(_repo, _compiled), do: {:ok, nil}

  defp run_metadata(manifest) do
    %{
      executor_harness_kind:
        normalize_metadata_value(get_in(manifest, ["executor", "harness", "kind"])),
      executor_harness_profile:
        normalize_metadata_value(get_in(manifest, ["executor", "harness", "profile"])),
      origin_kind: normalize_metadata_value(get_in(manifest, ["origin", "kind"])),
      origin_transport: normalize_metadata_value(get_in(manifest, ["origin", "transport"])),
      origin_session_id: normalize_metadata_value(get_in(manifest, ["origin", "session_id"]))
    }
  end

  defp list_claims(artifact_id),
    do:
      Repo.all(
        from claim in Claim, where: claim.artifact_id == ^artifact_id, order_by: claim.ordinal
      )

  defp list_sources(node_id),
    do:
      Repo.all(from source in Source, where: source.node_id == ^node_id, order_by: source.ordinal)

  defp list_findings(review_id),
    do:
      Repo.all(
        from finding in Finding, where: finding.review_id == ^review_id, order_by: finding.ordinal
      )

  defp preload_node(nil), do: nil

  defp preload_node(node),
    do: Repo.preload(node, [:artifact, :run, :review, :state, :payload_files])

  defp map_get(map, string_key, atom_key), do: Map.get(map, string_key, Map.get(map, atom_key))

  defp normalize_metadata_value(nil), do: nil
  defp normalize_metadata_value(value) when is_binary(value), do: value
  defp normalize_metadata_value(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_metadata_value(value) when is_integer(value) or is_float(value),
    do: to_string(value)

  defp normalize_metadata_value(value) when is_boolean(value), do: to_string(value)

  defp normalize_metadata_value(value) when is_map(value) or is_list(value),
    do: Jason.encode!(value)

  defp normalize_metadata_value(value), do: to_string(value)

  defp node_type_from_header(%{"node_type" => 1}), do: "artifact"
  defp node_type_from_header(%{"node_type" => 2}), do: "run"
  defp node_type_from_header(%{"node_type" => 3}), do: "review"
  defp node_type_from_header(%{node_type: 1}), do: "artifact"
  defp node_type_from_header(%{node_type: 2}), do: "run"
  defp node_type_from_header(%{node_type: 3}), do: "review"
  defp node_type_from_header(_header), do: nil

  defp node_type_value("artifact"), do: 1
  defp node_type_value("run"), do: 2
  defp node_type_value("review"), do: 3
  defp node_type_value(value) when is_integer(value), do: value

  defp blank_to_nil("0x" <> zeroes) do
    if byte_size(zeroes) == 64 and zeroes == String.duplicate("0", 64),
      do: nil,
      else: "0x" <> zeroes
  end

  defp blank_to_nil(value), do: value

  defp normalize_block_time(nil), do: nil
  defp normalize_block_time(%DateTime{} = value), do: value

  defp normalize_block_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end
end
