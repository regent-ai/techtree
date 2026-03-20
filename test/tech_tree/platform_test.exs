defmodule TechTree.PlatformTest do
  use TechTree.DataCase, async: true

  import TechTree.PlatformFixtures

  alias TechTree.Platform

  test "dashboard_snapshot reflects imported platform rows" do
    agent = agent_fixture(%{display_name: "Atlas Regent"})

    tile =
      explorer_tile_fixture(%{coord_key: "1:2", x: 1, y: 2, owner_address: agent.owner_address})

    name_claim_fixture(%{fqdn: "atlas.agent.ethereum.eth", owner_address: agent.owner_address})
    redeem_claim_fixture(%{wallet_address: agent.owner_address})

    snapshot = Platform.dashboard_snapshot()

    assert snapshot.counts.agents == 1
    assert snapshot.counts.tiles == 1
    assert snapshot.counts.names == 1
    assert snapshot.counts.redeems == 1
    assert [%{display_name: "Atlas Regent"}] = snapshot.recent_agents

    assert [%{coord_key: "1:2", child_count: 0, parent_coord_key: nil}] =
             Platform.list_tiles_json()

    assert tile.coord_key == "1:2"
  end

  test "explorer snapshot derives roots and descendants from metadata parent pointers" do
    explorer_tile_fixture(%{coord_key: "0:0", x: 0, y: 0, title: "Root"})

    explorer_tile_fixture(%{
      coord_key: "1:0",
      x: 1,
      y: 0,
      title: "Child",
      metadata: %{"parent_coord_key" => "0:0"}
    })

    explorer_tile_fixture(%{
      coord_key: "2:0",
      x: 2,
      y: 0,
      title: "Grandchild",
      metadata: %{"parent_coord_key" => "1:0"}
    })

    snapshot = Platform.explorer_snapshot()

    assert ["0:0"] == Enum.map(snapshot.root_tiles, & &1.coord_key)

    assert ["1:0"] ==
             snapshot |> Platform.explorer_view_tiles(["0:0"]) |> Enum.map(& &1.coord_key)

    assert ["2:0"] ==
             snapshot |> Platform.explorer_view_tiles(["0:0", "1:0"]) |> Enum.map(& &1.coord_key)

    assert Platform.explorer_child_count(snapshot, "0:0") == 1
    assert Platform.explorer_child_count(snapshot, "1:0") == 1
    assert Platform.explorer_child_count(snapshot, "2:0") == 0
  end

  test "list_agents applies search and status filters" do
    agent_fixture(%{display_name: "Alpha Regent", status: "active", owner_address: "0x100"})

    matched =
      agent_fixture(%{display_name: "Gamma Regent", status: "ready", owner_address: "0x200"})

    agent_fixture(%{display_name: "Delta Regent", status: "failed", owner_address: "0x300"})

    assert [%{slug: slug}] = Platform.list_agents(limit: 10, search: "Gamma", status: "ready")
    assert slug == matched.slug

    assert Enum.empty?(Platform.list_agents(limit: 10, search: "Gamma", status: "active"))
  end

  test "names_snapshot preserves basenames credits, allowances, and ens claims" do
    name_claim_fixture(%{fqdn: "alpha.agent.ethereum.eth"})
    basename_mint_allowance_fixture(%{address: "0xallowance"})

    basename_payment_credit_fixture(%{
      address: "0xcredit",
      payment_tx_hash: "0x" <> String.duplicate("1", 64)
    })

    ens_subname_claim_fixture(%{fqdn: "ens.agent.ethereum.eth"})

    snapshot = Platform.names_snapshot()

    assert [%{fqdn: "alpha.agent.ethereum.eth"}] = snapshot.recent
    assert [%{address: "0xallowance"}] = snapshot.allowances
    assert [%{address: "0xcredit"}] = snapshot.credits
    assert [%{fqdn: "ens.agent.ethereum.eth"}] = snapshot.ens_claims
    assert snapshot.available_credit_count == 1
    assert snapshot.ens_claim_count == 1
    assert snapshot.allowance_count == 1
  end
end
