defmodule TechTreeWeb.PublicMiscControllersTest do
  use TechTreeWeb.ConnCase, async: true

  alias TechTree.Activity
  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  test "GET /health returns service status", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/health")
      |> json_response(200)

    assert response == %{"ok" => true, "service" => "tech_tree"}
  end

  test "GET /v1/tree/search returns a stable error when q is missing", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/v1/tree/search")
      |> json_response(422)

    assert %{
             "error" => %{
               "code" => "search_query_required",
               "product" => "techtree",
               "status" => 422,
               "path" => "/v1/tree/search"
             }
           } = response
  end

  test "GET /v1/tree/activity returns encoded events", %{conn: conn} do
    _ = Activity.log!("economic.reward_earned", :agent, 123, nil, %{"amount" => "1"})

    response =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/v1/tree/activity")
      |> json_response(200)

    assert %{"data" => [%{"event_type" => "economic.reward_earned", "stream" => "economic"} | _]} =
             response
  end

  test "GET /v1/tree/seeds/:seed/hot filters by seed", %{conn: conn} do
    creator = create_agent!("seed-hot")

    included =
      create_node!(creator, %{
        seed: "ML",
        title: "seed-hot-include",
        activity_score: Decimal.new("9.0")
      })

    _excluded =
      create_node!(creator, %{
        seed: "DeFi",
        title: "seed-hot-exclude",
        activity_score: Decimal.new("10.0")
      })

    response =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/v1/tree/seeds/ML/hot")
      |> json_response(200)

    assert Enum.any?(response["data"], &(&1["id"] == included.id and &1["seed"] == "ML"))
    assert Enum.all?(response["data"], &(&1["seed"] == "ML"))
  end

  defp create_agent!(label_prefix) do
    unique = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => "8453",
      "registry_address" => "0x#{label_prefix}registry#{unique}",
      "token_id" => Integer.to_string(unique),
      "wallet_address" => "0x#{label_prefix}wallet#{unique}",
      "label" => "#{label_prefix}-#{unique}"
    })
  end

  defp create_node!(creator, attrs) do
    unique = System.unique_integer([:positive])

    base_attrs = %{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :hypothesis,
      title: "public-seed-node-#{unique}",
      status: :anchored,
      notebook_source: "print('node')",
      publish_idempotency_key: "public-seed-node:#{unique}",
      creator_agent_id: creator.id
    }

    %Node{}
    |> Ecto.Changeset.change(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end
end
