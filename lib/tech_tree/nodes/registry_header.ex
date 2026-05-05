defmodule TechTree.Nodes.RegistryHeader do
  @moduledoc false

  alias TechTree.Nodes.Node

  @zero_bytes32 "0x0000000000000000000000000000000000000000000000000000000000000000"

  @spec publish_params!(Node.t()) :: map()
  def publish_params!(%Node{} = node) do
    %{
      node_id: bytes32!(node.id, :node_id),
      subject_id: bytes32!(node.parent_id || 0, :subject_id),
      aux_id: @zero_bytes32,
      payload_hash: payload_hash!(node),
      node_type: node_type!(node.kind),
      schema_version: 1,
      flags: 0,
      author: creator_wallet!(node),
      manifest_cid: required_text!(node.manifest_cid, :manifest_cid, node.id),
      payload_cid: required_text!(node.notebook_cid, :payload_cid, node.id)
    }
  end

  @spec receipt_verification!(Node.t()) :: map()
  def receipt_verification!(%Node{} = node) do
    params = publish_params!(node)

    %{
      "node_id" => params.node_id,
      "manifest_cid" => params.manifest_cid,
      "payload_cid" => params.payload_cid,
      "author" => params.author,
      "header" => %{
        "id" => params.node_id,
        "subject_id" => params.subject_id,
        "aux_id" => params.aux_id,
        "payload_hash" => "sha256:" <> String.replace_prefix(params.payload_hash, "0x", ""),
        "node_type" => params.node_type,
        "schema_version" => params.schema_version,
        "flags" => params.flags,
        "author" => params.author
      }
    }
  end

  @spec node_type!(atom()) :: 1 | 2 | 3
  def node_type!(:hypothesis), do: 1
  def node_type!(:data), do: 1
  def node_type!(:synthesis), do: 1
  def node_type!(:meta), do: 1
  def node_type!(:skill), do: 1
  def node_type!(:eval), do: 1
  def node_type!(:result), do: 2
  def node_type!(:null_result), do: 2
  def node_type!(:review), do: 3

  def node_type!(kind),
    do: raise(ArgumentError, "unsupported registry node kind #{inspect(kind)}")

  defp creator_wallet!(%Node{creator_agent: %{wallet_address: wallet}, id: node_id}) do
    required_text!(wallet, :creator_wallet, node_id)
  end

  defp creator_wallet!(%Node{id: node_id}),
    do: raise(ArgumentError, "creator wallet missing for node #{node_id}")

  defp payload_hash!(%Node{} = node) do
    hash =
      node.manifest_hash
      |> required_text!(:manifest_hash, node.id)
      |> String.trim()
      |> String.replace_prefix("sha256:", "")
      |> String.replace_prefix("0x", "")
      |> String.replace_prefix("0X", "")

    if Regex.match?(~r/^[0-9a-fA-F]{64}$/, hash) do
      "0x" <> String.downcase(hash)
    else
      raise ArgumentError, "manifest_hash for node #{node.id} must be a 32-byte hex digest"
    end
  end

  defp bytes32!(value, _field) when is_integer(value) and value >= 0 do
    "0x" <> String.pad_leading(Integer.to_string(value, 16), 64, "0")
  end

  defp bytes32!("0x" <> hash, field), do: bytes32!(hash, field)
  defp bytes32!("0X" <> hash, field), do: bytes32!(hash, field)

  defp bytes32!(hash, _field) when is_binary(hash) do
    normalized = String.trim(hash)

    if Regex.match?(~r/^[0-9a-fA-F]{64}$/, normalized) do
      "0x" <> String.downcase(normalized)
    else
      raise ArgumentError, "registry node ids must be 32-byte hex values"
    end
  end

  defp bytes32!(_value, field),
    do: raise(ArgumentError, "invalid registry #{field}")

  defp required_text!(value, field, node_id) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      raise ArgumentError, "#{field} missing for node #{node_id}"
    else
      trimmed
    end
  end

  defp required_text!(_value, field, node_id),
    do: raise(ArgumentError, "#{field} missing for node #{node_id}")
end
