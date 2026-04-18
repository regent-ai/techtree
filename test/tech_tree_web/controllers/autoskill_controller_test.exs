defmodule TechTreeWeb.AutoskillControllerTest do
  use TechTreeWeb.ConnCase, async: true

  alias Decimal, as: D
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Autoskill.NodeBundle
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  test "public free bundle endpoint returns bundle metadata", %{conn: conn} do
    %{skill: skill} = autoskill_fixture!()

    assert %{
             "data" => %{
               "node_id" => node_id,
               "bundle_uri" => "ipfs://bafy-free-bundle",
               "download_url" => download_url,
               "marimo_entrypoint" => "session.marimo.py",
               "primary_file" => "SKILL.md"
             }
           } =
             conn
             |> put_req_header("accept", "application/json")
             |> get("/v1/autoskill/versions/#{skill.id}/bundle")
             |> json_response(200)

    assert node_id == skill.id
    assert String.contains?(download_url, "bafy-free-bundle")
  end

  test "gated bundle endpoint requires a verified purchase", %{conn: conn} do
    %{eval: eval_node} = autoskill_fixture!()

    assert %{"error" => %{"code" => "autoskill_payment_required"}} =
             conn
             |> put_req_header("accept", "application/json")
             |> get("/v1/autoskill/versions/#{eval_node.id}/bundle")
             |> json_response(402)
  end

  defp autoskill_fixture! do
    agent = insert_agent_fixture!()
    skill = insert_node!(agent, "Skills", :skill, %{skill_slug: "router", skill_version: "0.1.0"})
    eval_node = insert_node!(agent, "Evals", :eval, %{slug: "router-benchmark"})

    Repo.insert!(%NodeBundle{
      node_id: skill.id,
      bundle_type: :skill,
      access_mode: :public_free,
      preview_md: "# Prompt router",
      bundle_manifest: %{"metadata" => %{"version" => "0.1.0"}},
      primary_file: "SKILL.md",
      marimo_entrypoint: "session.marimo.py",
      bundle_uri: "ipfs://bafy-free-bundle",
      bundle_cid: "bafy-free-bundle",
      bundle_hash: "free-hash"
    })

    Repo.insert!(%NodeBundle{
      node_id: eval_node.id,
      bundle_type: :eval,
      access_mode: :gated_paid,
      preview_md: "# Benchmark",
      bundle_manifest: %{"metadata" => %{"version" => "0.1.0"}},
      primary_file: "scenario.yaml",
      marimo_entrypoint: "session.marimo.py",
      encrypted_bundle_uri: "ipfs://bafy-gated-bundle",
      encrypted_bundle_cid: "bafy-gated-bundle",
      payment_rail: :onchain,
      access_policy: %{"price" => "25.000000"}
    })

    %{skill: skill, eval: eval_node}
  end

  defp insert_node!(agent, seed, kind, attrs) do
    root = Nodes.create_seed_root!(seed, seed)
    uniq = System.unique_integer([:positive])

    Repo.insert!(%Node{
      path: "n#{root.id}.n#{uniq}",
      depth: 1,
      seed: seed,
      kind: kind,
      title: "#{seed}-#{uniq}",
      slug: Map.get(attrs, :slug),
      summary: "Autoskill bundle node",
      status: :anchored,
      publish_idempotency_key: "autoskill-controller-#{uniq}",
      notebook_source: "# notebook",
      parent_id: root.id,
      creator_agent_id: agent.id,
      skill_slug: Map.get(attrs, :skill_slug),
      skill_version: Map.get(attrs, :skill_version),
      skill_md_body: if(kind == :skill, do: "# Prompt router", else: nil),
      activity_score: D.new("10")
    })
  end

  defp insert_agent_fixture! do
    token = System.unique_integer([:positive])
    wallet_suffix = String.pad_leading(Integer.to_string(rem(token, 999_999), 16), 40, "0")

    Repo.insert!(%AgentIdentity{
      chain_id: 84_532,
      registry_address: "0x0000000000000000000000000000000000000001",
      token_id: D.new(token),
      wallet_address: "0x#{wallet_suffix}",
      label: "autoskill-controller-#{token}",
      status: "active"
    })
  end
end
