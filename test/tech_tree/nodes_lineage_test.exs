defmodule TechTree.NodesLineageTest do
  use TechTree.DataCase, async: true

  alias TechTree.Nodes
  alias TechTree.Repo
  alias TechTree.PhaseDApiSupport

  test "author link replacement preserves history and clear withdraws the active row" do
    author = PhaseDApiSupport.create_agent!("lineage-author")

    first_target =
      author
      |> PhaseDApiSupport.create_ready_node!(title: "first-target")
      |> with_chain_id!(8453)

    second_target =
      author
      |> PhaseDApiSupport.create_ready_node!(title: "second-target")
      |> with_chain_id!(8453)

    subject =
      PhaseDApiSupport.create_ready_node!(author,
        title: "subject-node"
      )
      |> with_chain_id!(8453)

    assert {:ok, first_link} =
             Nodes.create_or_replace_node_cross_chain_link(subject, author, %{
               "relation" => "reproduces",
               "target_chain_id" => 8_453,
               "target_node_ref" => "base:first-target",
               "target_node_id" => first_target.id,
               "note" => "Initial author link"
             })

    assert is_nil(first_link.withdrawn_at)

    assert {:ok, second_link} =
             Nodes.create_or_replace_node_cross_chain_link(subject, author, %{
               "relation" => "adaptation_of",
               "target_chain_id" => 8453,
               "target_node_ref" => "base:second-target",
               "target_node_id" => second_target.id,
               "note" => "Replacement author link"
             })

    assert second_link.id != first_link.id

    [latest, previous] = Nodes.list_node_cross_chain_links(subject)
    assert latest.id == second_link.id
    assert is_nil(latest.withdrawn_at)
    assert previous.id == first_link.id
    assert previous.withdrawn_reason == "replaced"
    assert not is_nil(previous.withdrawn_at)

    assert :ok = Nodes.clear_node_cross_chain_link(subject, author)

    [cleared_latest, _older] = Nodes.list_node_cross_chain_links(subject)
    assert cleared_latest.id == second_link.id
    assert cleared_latest.withdrawn_reason == "cleared"
    assert not is_nil(cleared_latest.withdrawn_at)
  end

  test "lineage claims are withdraw-only and only the claimant can withdraw" do
    author = PhaseDApiSupport.create_agent!("lineage-author")
    claimant = PhaseDApiSupport.create_agent!("lineage-claimant")
    outsider = PhaseDApiSupport.create_agent!("lineage-outsider")

    target =
      author
      |> PhaseDApiSupport.create_ready_node!(title: "mainnet-node")
      |> with_chain_id!(8453)

    subject =
      PhaseDApiSupport.create_ready_node!(author,
        title: "base-node"
      )
      |> with_chain_id!(8453)

    assert {:ok, claim} =
             Nodes.create_node_lineage_claim(subject, claimant, %{
               "relation" => "copy_of",
               "target_chain_id" => 8_453,
               "target_node_ref" => "base:mainnet-node",
               "target_node_id" => target.id,
               "note" => "Looks like a direct repost"
             })

    assert {:error, :claim_not_owned} =
             Nodes.withdraw_node_lineage_claim(subject, claim.id, outsider)

    assert :ok = Nodes.withdraw_node_lineage_claim(subject, claim.id, claimant)

    [withdrawn_claim] = Nodes.list_node_lineage_claims(subject)
    assert withdrawn_claim.id == claim.id
    assert not is_nil(withdrawn_claim.withdrawn_at)
  end

  test "projection marks mutual author links and conflicting claims as disputed" do
    author = PhaseDApiSupport.create_agent!("lineage-author")
    claimant = PhaseDApiSupport.create_agent!("lineage-claimant")

    mainnet =
      PhaseDApiSupport.create_ready_node!(author,
        title: "mainnet-origin"
      )
      |> with_chain_id!(8453)

    base =
      PhaseDApiSupport.create_ready_node!(author,
        title: "base-reproduction"
      )
      |> with_chain_id!(8453)

    assert {:ok, _} =
             Nodes.create_or_replace_node_cross_chain_link(base, author, %{
               "relation" => "reproduces",
               "target_chain_id" => 8_453,
               "target_node_ref" => "base:mainnet-origin",
               "target_node_id" => mainnet.id,
               "note" => "Ported to Base."
             })

    assert {:ok, _} =
             Nodes.create_or_replace_node_cross_chain_link(mainnet, author, %{
               "relation" => "backported_from",
               "target_chain_id" => 8453,
               "target_node_ref" => "base:base-reproduction",
               "target_node_id" => base.id,
               "note" => "Linked back to the Base version."
             })

    assert {:ok, _} =
             Nodes.create_node_lineage_claim(base, claimant, %{
               "relation" => "copy_of",
               "target_chain_id" => 8_453,
               "target_node_ref" => "base:other-node",
               "note" => "Another agent says this points somewhere else."
             })

    projection =
      base.id
      |> Nodes.get_public_node!()
      |> Nodes.cross_chain_lineage()

    assert projection.status == "disputed"
    assert projection.author_claim.mutual
    assert projection.author_claim.disputed
    assert Enum.any?(projection.claims, &(&1.disputed and &1.relation == "copy_of"))
  end

  defp with_chain_id!(node, chain_id) do
    node
    |> Ecto.Changeset.change(chain_id: chain_id)
    |> Repo.update!()
  end
end
