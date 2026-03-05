defmodule TechTree.IPFS.NodeManifest do
  @moduledoc false

  @spec render!(TechTree.Nodes.Node.t(), map(), keyword()) :: String.t()
  def render!(node, artifacts, opts \\ []) do
    sidelinks =
      opts
      |> Keyword.get(:sidelinks, [])
      |> Enum.map(fn edge ->
        %{
          "node_id" => edge[:node_id] || edge["node_id"],
          "tag" => edge[:tag] || edge["tag"],
          "ordinal" => edge[:ordinal] || edge["ordinal"]
        }
      end)

    creator = %{
      "type" => "agent",
      "chain_id" => node.creator_agent.chain_id,
      "registry_address" => node.creator_agent.registry_address,
      "token_id" => decimal_to_string(node.creator_agent.token_id),
      "wallet_address" => node.creator_agent.wallet_address
    }

    manifest = %{
      "version" => "techtree-node-manifest@1",
      "node_id" => node.id,
      "parent_id" => node.parent_id,
      "path" => node.path,
      "seed" => node.seed,
      "kind" => Atom.to_string(node.kind),
      "title" => node.title,
      "slug" => node.slug,
      "summary" => node.summary,
      "creator" => creator,
      "sidelinks" => sidelinks,
      "artifacts" => build_artifacts(artifacts),
      "hashes" => build_hashes(artifacts),
      "timestamps" => %{
        "created_at" => DateTime.to_iso8601(node.inserted_at || DateTime.utc_now())
      }
    }

    Jason.encode_to_iodata!(manifest, pretty: true)
    |> IO.iodata_to_binary()
  end

  @spec build_artifacts(map()) :: map()
  defp build_artifacts(artifacts) do
    base = %{"notebook_py" => "ipfs://#{artifacts.notebook_cid}"}

    case artifacts[:skill_md_cid] do
      nil -> base
      cid -> Map.put(base, "skill_md", "ipfs://#{cid}")
    end
  end

  @spec build_hashes(map()) :: map()
  defp build_hashes(artifacts) do
    base = %{"notebook_sha256" => artifacts.notebook_sha256}

    case artifacts[:skill_md_sha256] do
      nil -> base
      sha -> Map.put(base, "skill_md_sha256", sha)
    end
  end

  @spec decimal_to_string(Decimal.t() | term()) :: String.t()
  defp decimal_to_string(%Decimal{} = decimal), do: Decimal.to_string(decimal, :normal)
  defp decimal_to_string(other), do: to_string(other)
end
