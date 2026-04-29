defmodule TechTree.V1.CoreBridge do
  @moduledoc false

  @core_dir Path.expand("../../../core", __DIR__)
  @python_verify_script """
  import json
  import sys

  from techtree_core.canonical import bytes32_hex_from_digest, domain_hash, sha256_prefixed
  from techtree_core.compiler import _artifact_header, _review_header, _run_header
  from techtree_core.models import (
      ArtifactManifestV1,
      NodeHeaderV1,
      PayloadIndexV1,
      ReviewManifestV1,
      RunManifestV1,
  )

  MODELS = {
      "artifact": (ArtifactManifestV1, "TECHTREE-ARTIFACT-V1", _artifact_header),
      "run": (RunManifestV1, "TECHTREE-RUN-V1", _run_header),
      "review": (ReviewManifestV1, "TECHTREE-REVIEW-V1", _review_header),
  }

  if len(sys.argv) > 1:
      with open(sys.argv[1], "r", encoding="utf-8") as fh:
          payload = json.load(fh)
  else:
      payload = json.load(sys.stdin)
  node_type = payload["node_type"]
  manifest_cls, domain, header_fn = MODELS[node_type]
  manifest = manifest_cls.model_validate(payload["manifest"])
  payload_index = PayloadIndexV1.model_validate(payload["payload_index"])
  header = NodeHeaderV1.model_validate(payload["header"])

  payload_json = payload_index.model_dump(exclude_none=True, mode="json")
  payload_hash = sha256_prefixed("TECHTREE-PAYLOAD-V1", payload_json)
  manifest_json = manifest.model_dump(exclude_none=True, mode="json")
  node_id = bytes32_hex_from_digest(domain_hash(domain, manifest_json))
  expected_header = header_fn(manifest, node_id, payload_hash, header.author)
  header_json = header.model_dump(exclude_none=True, mode="json")
  expected_header_json = expected_header.model_dump(exclude_none=True, mode="json")

  print(
      json.dumps(
          {
              "ok": node_id == header.id and payload_hash == manifest.payload_hash and expected_header_json == header_json,
              "node_type": node_type,
              "node_id": node_id,
              "payload_hash": payload_hash,
              "header_match": expected_header_json == header_json,
              "payload_hash_match": payload_hash == manifest.payload_hash and payload_hash == header.payload_hash,
              "expected_header": expected_header_json,
          },
          indent=2,
          sort_keys=True,
      )
  )
  """

  def compile(path, author \\ nil) do
    args = ["-m", "techtree_core"]
    args = args ++ base_args(author) ++ ["compile", path]
    run_json(args)
  end

  def verify_workspace(path, author \\ nil) do
    args = ["-m", "techtree_core"]
    args = args ++ base_args(author) ++ ["verify", path]
    run_json(args)
  end

  def export_schemas(output_dir) do
    args = ["-m", "techtree_core", "schema-export", output_dir]
    run_json(args)
  end

  def verify_compiled(node_type, manifest, payload_index, header) do
    run_json_with_input_file(
      ["-c", @python_verify_script],
      %{
        node_type: to_string(node_type),
        manifest: manifest,
        payload_index: payload_index,
        header: header
      }
    )
  end

  defp base_args(nil), do: []
  defp base_args(""), do: []
  defp base_args(author), do: ["--author", author]

  defp run_json(python_args) do
    case run_uv(["run", "--directory", @core_dir, "python" | python_args]) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, {:invalid_json, Exception.message(reason), output}}
        end

      {output, status} when is_binary(output) and is_integer(status) ->
        {:error, {:command_failed, status, String.trim(output)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_uv(args) do
    task = Task.async(fn -> System.cmd("uv", args, stderr_to_stdout: true) end)

    receive do
      {ref, result} when ref == task.ref ->
        Process.demonitor(task.ref, [:flush])
        result

      {:DOWN, ref, :process, _pid, reason} when ref == task.ref ->
        {:error, {:command_failed, reason}}
    after
      60_000 ->
        Task.shutdown(task, :brutal_kill)
        {:error, {:command_timeout, 60_000}}
    end
  end

  defp run_json_with_input_file(python_args, input) do
    temp_path =
      System.tmp_dir!()
      |> Path.join("techtree-core-#{System.unique_integer([:positive])}.json")

    File.write!(temp_path, Jason.encode!(input))

    try do
      run_json(python_args ++ [temp_path])
    after
      File.rm(temp_path)
    end
  end
end
