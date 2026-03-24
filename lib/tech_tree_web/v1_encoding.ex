defmodule TechTreeWeb.V1Encoding do
  @moduledoc false

  def encode_node(nil), do: nil

  def encode_node(node) do
    base = %{
      id: node.id,
      node_type: node_type_name(node.node_type),
      author: node.author,
      subject_id: node.subject_id,
      aux_id: node.aux_id,
      payload_hash: node.payload_hash,
      manifest_cid: node.manifest_cid,
      payload_cid: node.payload_cid,
      schema_version: node.schema_version,
      tx_hash: node.tx_hash,
      block_number: node.block_number,
      block_time: node.block_time,
      verification_status: node.verification_status,
      verification_error: node.verification_error,
      header: node.header,
      manifest: node.manifest,
      payload_index: node.payload_index,
      state: encode_state(node.state),
      payload_files: Enum.map(node.payload_files || [], &encode_payload_file/1)
    }

    case encode_run_summary(node.run, node.manifest) do
      nil -> base
      run -> Map.put(base, :run, run)
    end
  end

  def encode_artifact_bundle(nil), do: nil

  def encode_artifact_bundle(%{node: node, artifact: artifact} = bundle) do
    %{
      node: encode_node(node),
      artifact: %{
        id: artifact.id,
        kind: artifact.kind,
        title: artifact.title,
        summary: artifact.summary,
        has_eval: artifact.has_eval,
        eval_mode: artifact.eval_mode
      },
      parents: Enum.map(bundle.parents, &encode_parent_edge/1),
      children: Enum.map(bundle.children, &encode_child_edge/1),
      runs: Enum.map(bundle.runs, &encode_run_summary/1),
      claims: Enum.map(bundle.claims, &encode_claim/1),
      sources: Enum.map(bundle.sources, &encode_source/1)
    }
  end

  def encode_run_bundle(nil), do: nil

  def encode_run_bundle(%{node: node, run: run, artifact: artifact}) do
    %{
      node: encode_node(node),
      run: encode_run_summary(run, node.manifest),
      artifact: encode_artifact_bundle(artifact)
    }
  end

  def encode_review_bundle(nil), do: nil

  def encode_review_bundle(%{node: node, review: review, target: target, findings: findings}) do
    %{
      node: encode_node(node),
      review: %{
        id: review.id,
        target_type: review.target_type,
        target_id: review.target_id,
        kind: review.kind,
        method: review.method,
        result: review.result,
        scope_level: review.scope_level,
        scope_path: review.scope_path
      },
      target: encode_node(target),
      findings: Enum.map(findings, &encode_finding/1)
    }
  end

  def encode_run_summary(run), do: encode_run_summary(run, nil)

  def encode_search_results(nodes) do
    Enum.map(nodes, fn node ->
      base = %{
        id: node.id,
        node_type: node_type_name(node.node_type),
        title: node.artifact && node.artifact.title,
        summary: node.artifact && node.artifact.summary,
        executor_id: node.run && node.run.executor_id,
        executor_harness_kind: node.run && node.run.executor_harness_kind,
        executor_harness_profile: node.run && node.run.executor_harness_profile,
        origin_kind: node.run && node.run.origin_kind,
        origin_transport: node.run && node.run.origin_transport,
        origin_session_id: node.run && node.run.origin_session_id,
        review_result: node.review && node.review.result,
        state: encode_state(node.state)
      }

      case encode_run_summary(node.run, node.manifest) do
        nil -> base
        run -> Map.put(base, :run, run)
      end
    end)
  end

  defp encode_state(nil), do: nil

  defp encode_state(state) do
    %{
      validated: state.validated,
      challenged: state.challenged,
      retired: state.retired,
      latest_review_result: state.latest_review_result
    }
  end

  defp encode_payload_file(file) do
    %{
      path: file.path,
      sha256: file.sha256,
      size: file.size,
      media_type: file.media_type,
      role: file.role
    }
  end

  defp encode_parent_edge(edge) do
    %{
      relation: edge.relation,
      note: edge.note,
      parent: encode_node(edge.parent)
    }
  end

  defp encode_child_edge(edge) do
    %{
      relation: edge.relation,
      note: edge.note,
      child: encode_node(edge.child)
    }
  end

  defp encode_run_summary(nil, _manifest), do: nil

  defp encode_run_summary(run, manifest) do
    %{
      id: run.id,
      artifact_id: run.artifact_id,
      executor_type: run.executor_type,
      executor_id: run.executor_id,
      status: run.status,
      score: run.score,
      executor_harness_kind:
        run.executor_harness_kind ||
          run_manifest_value(manifest, ["executor", "harness", "kind"], "executor_harness_kind"),
      executor_harness_profile:
        run.executor_harness_profile ||
          run_manifest_value(
            manifest,
            ["executor", "harness", "profile"],
            "executor_harness_profile"
          ),
      origin_kind:
        run.origin_kind || run_manifest_value(manifest, ["origin", "kind"], "origin_kind"),
      origin_transport:
        run.origin_transport ||
          run_manifest_value(manifest, ["origin", "transport"], "origin_transport"),
      origin_session_id:
        run.origin_session_id ||
          run_manifest_value(manifest, ["origin", "session_id"], "origin_session_id")
    }
  end

  defp run_manifest_value(nil, _path, _keys), do: nil

  defp run_manifest_value(manifest, path, keys) when is_list(keys) do
    case get_in(manifest, path) do
      nil ->
        Enum.find_value(keys, fn key -> manifest[key] end)

      value ->
        value
    end
  end

  defp run_manifest_value(manifest, path, key), do: run_manifest_value(manifest, path, [key])

  defp encode_claim(claim) do
    %{ordinal: claim.ordinal, text: claim.text}
  end

  defp encode_source(source) do
    %{
      ordinal: source.ordinal,
      kind: source.kind,
      ref: source.ref,
      license: source.license,
      note: source.note
    }
  end

  defp encode_finding(finding) do
    %{
      ordinal: finding.ordinal,
      code: finding.code,
      severity: finding.severity,
      message: finding.message
    }
  end

  defp node_type_name(1), do: "artifact"
  defp node_type_name(2), do: "run"
  defp node_type_name(3), do: "review"
  defp node_type_name(other), do: to_string(other)
end
