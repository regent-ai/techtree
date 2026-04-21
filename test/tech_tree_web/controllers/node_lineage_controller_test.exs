defmodule TechTreeWeb.NodeLineageControllerTest do
  use TechTreeWeb.ConnCase, async: false

  alias TechTree.Agents
  alias TechTree.Nodes
  alias TechTree.PhaseDApiSupport
  alias TechTree.Repo

  test "public lineage endpoint and node show expose the normalized projection", %{conn: conn} do
    author = PhaseDApiSupport.create_agent!("lineage-public")

    target =
      PhaseDApiSupport.create_ready_node!(author,
        title: "target-mainnet"
      )
      |> with_chain_id!(8453)

    subject =
      PhaseDApiSupport.create_ready_node!(author,
        title: "subject-base"
      )
      |> with_chain_id!(8453)

    assert {:ok, _link} =
             Nodes.create_or_replace_node_cross_chain_link(subject, author, %{
               "relation" => "reproduces",
               "target_chain_id" => 8_453,
               "target_node_ref" => "base:target-mainnet",
               "target_node_id" => target.id,
               "note" => "Published on Base first."
             })

    assert %{
             "data" => %{
               "status" => "author_claimed",
               "author_claim" => %{
                 "relation" => "reproduces",
                 "target_chain_label" => "Base Mainnet"
               }
             }
           } =
             conn
             |> put_req_header("accept", "application/json")
             |> get("/v1/tree/nodes/#{subject.id}/lineage")
             |> json_response(200)

    assert %{
             "data" => %{
               "id" => id,
               "cross_chain_lineage" => %{
                 "author_claim" => %{"target_chain_label" => "Base Mainnet"}
               }
             }
           } =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> get("/v1/tree/nodes/#{subject.id}")
             |> json_response(200)

    assert id == subject.id
  end

  test "agent can create and withdraw lineage claims through the HTTP surface", %{conn: conn} do
    author = PhaseDApiSupport.create_agent!("lineage-author")
    claimant = create_agent_headers!("lineage-claimant")

    subject =
      PhaseDApiSupport.create_ready_node!(author,
        title: "claim-subject"
      )
      |> with_chain_id!(8453)

    response =
      conn
      |> with_siwa_headers(claimant)
      |> post("/v1/tree/nodes/#{subject.id}/lineage/claims", %{
        "relation" => "copy_of",
        "target_chain_id" => 8_453,
        "target_node_ref" => "base:claimed-source",
        "note" => "Looks copied from a mainnet original."
      })
      |> json_response(201)

    assert %{"data" => %{"id" => claim_id, "relation" => "copy_of"}} = response

    assert %{"data" => [claim]} =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(claimant)
             |> get("/v1/agent/tree/nodes/#{subject.id}/lineage/claims")
             |> json_response(200)

    assert claim["id"] == claim_id

    assert %{"ok" => true} =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(claimant)
             |> delete("/v1/tree/nodes/#{subject.id}/lineage/claims/#{claim_id}")
             |> json_response(200)

    assert %{"data" => [withdrawn]} =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(claimant)
             |> get("/v1/agent/tree/nodes/#{subject.id}/lineage/claims")
             |> json_response(200)

    assert withdrawn["id"] == claim_id
    assert is_binary(withdrawn["withdrawn_at"])
  end

  test "withdraw claim reports an invalid claim id separately from an invalid node id", %{
    conn: conn
  } do
    author = PhaseDApiSupport.create_agent!("lineage-invalid-claim-author")
    claimant = create_agent_headers!("lineage-invalid-claimant")

    subject =
      PhaseDApiSupport.create_ready_node!(author,
        title: "claim-invalid-subject"
      )
      |> with_chain_id!(8453)

    assert %{"error" => %{"code" => "invalid_claim_id"}} =
             conn
             |> with_siwa_headers(claimant)
             |> delete("/v1/tree/nodes/#{subject.id}/lineage/claims/not-a-claim")
             |> json_response(422)
  end

  test "only the node author can create and clear a cross-chain link", %{conn: conn} do
    author = create_agent_headers!("lineage-link-author")
    outsider = create_agent_headers!("lineage-link-outsider")

    subject =
      PhaseDApiSupport.create_ready_node!(author.agent,
        title: "author-subject"
      )
      |> with_chain_id!(8453)

    assert %{"error" => %{"code" => "node_author_required"}} =
             conn
             |> with_siwa_headers(outsider)
             |> post("/v1/tree/nodes/#{subject.id}/cross-chain-links", %{
               "relation" => "reproduces",
               "target_chain_id" => 8_453,
               "target_node_ref" => "base:forbidden"
             })
             |> json_response(403)

    assert %{"data" => %{"relation" => "reproduces"}} =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(author)
             |> post("/v1/tree/nodes/#{subject.id}/cross-chain-links", %{
               "relation" => "reproduces",
               "target_chain_id" => 8_453,
               "target_node_ref" => "base:allowed"
             })
             |> json_response(200)

    assert %{"ok" => true} =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(author)
             |> delete("/v1/tree/nodes/#{subject.id}/cross-chain-links/current")
             |> json_response(200)
  end

  defp create_agent_headers!(label_prefix) do
    unique = System.unique_integer([:positive])
    wallet = PhaseDApiSupport.random_eth_address()
    registry = PhaseDApiSupport.random_eth_address()
    token_id = Integer.to_string(unique)

    agent =
      Agents.upsert_verified_agent!(%{
        "chain_id" => "84532",
        "registry_address" => registry,
        "token_id" => token_id,
        "wallet_address" => wallet,
        "label" => "#{label_prefix}-#{unique}"
      })

    %{agent: agent, wallet: wallet, chain_id: "84532", registry: registry, token_id: token_id}
  end

  defp with_siwa_headers(conn, headers) do
    TechTreeWeb.TestSupport.SiwaIntegrationSupport.with_siwa_headers(conn,
      wallet: headers.wallet,
      chain_id: headers.chain_id,
      registry_address: headers.registry,
      token_id: headers.token_id
    )
  end

  defp with_chain_id!(node, chain_id) do
    node
    |> Ecto.Changeset.change(chain_id: chain_id)
    |> Repo.update!()
  end
end
