defmodule TechTreeWeb.PlatformApiControllerTest do
  use TechTreeWeb.ConnCase, async: true

  import TechTree.PlatformFixtures

  test "GET /api/platform/explorer/tiles returns LiveView tile payloads", %{conn: conn} do
    explorer_tile_fixture(%{
      coord_key: "4:7",
      x: 4,
      y: 7,
      title: "Signal Bloom",
      shader_key: "signal-bloom",
      terrain: "reef",
      owner_address: "0x123"
    })

    explorer_tile_fixture(%{
      coord_key: "5:7",
      x: 5,
      y: 7,
      title: "Child Tile",
      shader_key: "signal-bloom",
      metadata: %{"parent_coord_key" => "4:7"}
    })

    conn = get(conn, "/api/platform/explorer/tiles")

    assert %{
             "tiles" => [
               %{
                 "coord_key" => "4:7",
                 "terrain" => "reef",
                 "owner_address" => "0x123",
                 "child_count" => 1,
                 "parent_coord_key" => nil
               },
               %{
                 "coord_key" => "5:7",
                 "parent_coord_key" => "4:7",
                 "child_count" => 0
               }
             ]
           } =
             json_response(conn, 200)
  end
end
