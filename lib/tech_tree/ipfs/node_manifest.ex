defmodule TechTree.IPFS.NodeManifest do
  @moduledoc false

  @spec render!(TechTree.Nodes.Node.t(), map()) :: String.t()
  def render!(node, artifacts) do
    %{
      "version" => "techtree-node-manifest@1",
      "node_id" => node.id,
      "seed" => node.seed,
      "kind" => to_string(node.kind),
      "title" => node.title,
      "notebook_cid" => artifacts.notebook_cid,
      "created_at" => DateTime.to_iso8601(node.inserted_at || DateTime.utc_now())
    }
    |> maybe_put("skill_cid", artifacts[:skill_cid])
    |> maybe_put("parent_cid", artifacts[:parent_cid])
    |> then(&Jason.encode_to_iodata!(&1, pretty: true))
    |> IO.iodata_to_binary()
  end

  @spec maybe_put(map(), String.t(), term()) :: map()
  defp maybe_put(manifest, _key, value) when value in [nil, ""], do: manifest
  defp maybe_put(manifest, key, value), do: Map.put(manifest, key, value)
end
