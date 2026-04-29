defmodule TechTree.AutoskillTest do
  use TechTree.DataCase, async: true

  alias Decimal, as: D
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Autoskill
  alias TechTree.Autoskill.{Listing, NodeBundle, Result, Review}
  alias TechTree.NodeAccess
  alias TechTree.NodeAccess.NodePaidPayload
  alias TechTree.Nodes
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  setup do
    previous = Application.get_env(:tech_tree, :autoskill)

    Application.put_env(:tech_tree, :autoskill,
      chains: %{
        8453 => %{
          settlement_contract_address: "0x0000000000000000000000000000000000000845",
          usdc_token_address: "0x0000000000000000000000000000000000008453",
          treasury_address: "0x0000000000000000000000000000000000000999"
        }
      }
    )

    on_exit(fn ->
      if previous do
        Application.put_env(:tech_tree, :autoskill, previous)
      else
        Application.delete_env(:tech_tree, :autoskill)
      end
    end)

    :ok
  end

  test "create_skill_version mirrors preview markdown into the node and creates a bundle" do
    agent = insert_agent_fixture!("autoskill-author")

    assert {:ok, %{node: node, bundle: bundle}} =
             Autoskill.create_skill_version(agent, %{
               "title" => "Prompt router",
               "summary" => "Routes tasks to the right prompt set.",
               "skill_slug" => "prompt-router",
               "skill_version" => "0.1.0",
               "access_mode" => "public_free",
               "preview_md" => "# Prompt router\n",
               "bundle_manifest" => %{
                 "type" => "skill",
                 "metadata" => %{"version" => "0.1.0"}
               },
               "primary_file" => "SKILL.md",
               "marimo_entrypoint" => "session.marimo.py",
               "bundle_archive_b64" => Base.encode64(~s({"ok":true}))
             })

    persisted_node = Repo.get!(Node, node.id)
    persisted_bundle = Repo.get!(NodeBundle, bundle.id)

    assert persisted_node.kind == :skill
    assert persisted_node.skill_md_body == "# Prompt router"
    assert persisted_node.seed == "Skills"
    assert persisted_bundle.bundle_type == :skill
    assert persisted_bundle.access_mode == :public_free
    assert persisted_bundle.marimo_entrypoint == "session.marimo.py"
    assert is_binary(persisted_bundle.bundle_cid)
  end

  test "eligible_for_listing?/1 requires ten unique non-self replicable reviewers" do
    author = insert_agent_fixture!("autoskill-seller")

    skill =
      insert_bundle_backed_node!(author, "Skills", :skill, %{
        skill_slug: "router",
        skill_version: "0.1.0",
        access_mode: :gated_paid
      })

    eval_node = insert_bundle_backed_node!(author, "Evals", :eval, %{slug: "router-benchmark"})

    for index <- 1..10 do
      reviewer = insert_agent_fixture!("reviewer-#{index}")

      result =
        Repo.insert!(%Result{
          skill_node_id: skill.id,
          eval_node_id: eval_node.id,
          executor_agent_id: reviewer.id,
          runtime_kind: :local,
          trial_count: 1,
          raw_score: 0.7 + index / 100,
          normalized_score: 0.8 + index / 100
        })

      Repo.insert!(%Review{
        skill_node_id: skill.id,
        reviewer_agent_id: reviewer.id,
        kind: :replicable,
        result_id: result.id,
        runtime_kind: :local,
        reported_score: result.normalized_score
      })
    end

    assert Autoskill.eligible_for_listing?(skill.id)

    assert {:ok, %Listing{} = listing} =
             Autoskill.create_listing(author, skill.id, %{
               "payment_rail" => "onchain",
               "chain_id" => 8453,
               "usdc_token_address" => "0x0000000000000000000000000000000000008453",
               "treasury_address" => "0x0000000000000000000000000000000000000999",
               "seller_payout_address" => "0x0000000000000000000000000000000000000777",
               "price_usdc" => "25.000000"
             })

    assert listing.chain_id == 8453
    assert listing.treasury_bps == 100
    assert listing.seller_bps == 9900

    payload = Repo.get_by!(NodePaidPayload, node_id: skill.id)

    assert payload.status == :draft
    assert payload.chain_id == 8453
    assert payload.usdc_token_address == "0x0000000000000000000000000000000000008453"
    assert payload.treasury_address == "0x0000000000000000000000000000000000000999"
    assert payload.seller_payout_address == "0x0000000000000000000000000000000000000777"
    assert D.equal?(payload.price_usdc, D.new("25.000000"))
  end

  test "only the skill creator can create its paid listing" do
    author = insert_agent_fixture!("autoskill-owner")
    other_agent = insert_agent_fixture!("autoskill-not-owner")

    skill =
      insert_bundle_backed_node!(author, "Skills", :skill, %{
        skill_slug: "owner-only-router",
        skill_version: "0.1.0",
        access_mode: :gated_paid
      })

    eval_node =
      insert_bundle_backed_node!(author, "Evals", :eval, %{slug: "owner-only-router-benchmark"})

    for index <- 1..10 do
      reviewer = insert_agent_fixture!("owner-only-reviewer-#{index}")

      result =
        Repo.insert!(%Result{
          skill_node_id: skill.id,
          eval_node_id: eval_node.id,
          executor_agent_id: reviewer.id,
          runtime_kind: :local,
          trial_count: 1,
          raw_score: 0.7 + index / 100,
          normalized_score: 0.8 + index / 100
        })

      Repo.insert!(%Review{
        skill_node_id: skill.id,
        reviewer_agent_id: reviewer.id,
        kind: :replicable,
        result_id: result.id,
        runtime_kind: :local,
        reported_score: result.normalized_score
      })
    end

    assert Autoskill.eligible_for_listing?(skill.id)

    assert {:error, :autoskill_listing_creator_required} =
             Autoskill.create_listing(other_agent, skill.id, listing_attrs())

    refute Repo.get_by(Listing, skill_node_id: skill.id)
    assert Repo.get_by!(NodePaidPayload, node_id: skill.id).seller_agent_id == author.id

    assert {:ok, %Listing{} = listing} =
             Autoskill.create_listing(author, skill.id, listing_attrs())

    assert listing.seller_agent_id == author.id
    assert Repo.get_by!(NodePaidPayload, node_id: skill.id).seller_agent_id == author.id
  end

  defp listing_attrs do
    %{
      "payment_rail" => "onchain",
      "chain_id" => 8453,
      "usdc_token_address" => "0x0000000000000000000000000000000000008453",
      "treasury_address" => "0x0000000000000000000000000000000000000999",
      "seller_payout_address" => "0x0000000000000000000000000000000000000777",
      "price_usdc" => "25.000000"
    }
  end

  defp insert_bundle_backed_node!(agent, seed, kind, attrs) do
    root = Nodes.create_seed_root!(seed, seed)
    uniq = System.unique_integer([:positive])

    node =
      Repo.insert!(%Node{
        path: "n#{root.id}.n#{uniq}",
        depth: 1,
        seed: seed,
        kind: kind,
        title: Map.get(attrs, :title, "#{seed}-#{uniq}"),
        slug: Map.get(attrs, :slug),
        summary: "Autoskill test node",
        status: :anchored,
        publish_idempotency_key: "autoskill-test-#{uniq}",
        notebook_source: "# notebook",
        parent_id: root.id,
        creator_agent_id: agent.id,
        skill_slug: Map.get(attrs, :skill_slug),
        skill_version: Map.get(attrs, :skill_version),
        skill_md_body: if(kind == :skill, do: "# preview", else: nil),
        activity_score: D.new("10")
      })

    bundle =
      Repo.insert!(%NodeBundle{
        node_id: node.id,
        bundle_type: if(kind == :skill, do: :skill, else: :eval),
        access_mode: Map.get(attrs, :access_mode, :public_free),
        preview_md: "# preview",
        bundle_manifest: %{"metadata" => %{"version" => "0.1.0"}},
        primary_file: if(kind == :skill, do: "SKILL.md", else: "scenario.yaml"),
        marimo_entrypoint: "session.marimo.py",
        bundle_uri:
          if(Map.get(attrs, :access_mode, :public_free) == :public_free,
            do: "ipfs://bafy#{uniq}",
            else: nil
          ),
        bundle_cid:
          if(Map.get(attrs, :access_mode, :public_free) == :public_free,
            do: "bafy#{uniq}",
            else: nil
          ),
        bundle_hash: "hash#{uniq}",
        encrypted_bundle_uri:
          if(Map.get(attrs, :access_mode, :public_free) == :gated_paid,
            do: "ipfs://enc#{uniq}",
            else: nil
          ),
        encrypted_bundle_cid:
          if(Map.get(attrs, :access_mode, :public_free) == :gated_paid,
            do: "enc#{uniq}",
            else: nil
          ),
        payment_rail:
          if(Map.get(attrs, :access_mode, :public_free) == :gated_paid, do: :onchain, else: nil),
        access_policy:
          if(Map.get(attrs, :access_mode, :public_free) == :gated_paid,
            do: %{"price" => "25.000000"},
            else: nil
          )
      })

    NodeAccess.sync_autoskill_bundle(node, agent, bundle)

    node
  end

  defp insert_agent_fixture!(label_prefix) do
    token = System.unique_integer([:positive])
    suffix = Integer.to_string(token)
    wallet_suffix = String.pad_leading(Integer.to_string(rem(token, 999_999), 16), 40, "0")

    Repo.insert!(%AgentIdentity{
      chain_id: 84_532,
      registry_address: "0x0000000000000000000000000000000000000001",
      token_id: D.new(token),
      wallet_address: "0x#{wallet_suffix}",
      label: "#{label_prefix}-#{suffix}",
      status: "active"
    })
  end
end
