defmodule TechTreeWeb.TechControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import TechTreeWeb.TestSupport.SiwaIntegrationSupport

  alias TechTree.Agents
  alias TechTree.Tech

  setup do
    Application.put_env(:tech_tree, :tech,
      chain_id: 8453,
      token_address: "0x0000000000000000000000000000000000001001",
      reward_router_address: "0x0000000000000000000000000000000000001002",
      agent_reward_vault_address: "0x0000000000000000000000000000000000001003",
      emission_controller_address: "0x0000000000000000000000000000000000001004",
      leaderboard_registry_address: "0x0000000000000000000000000000000000001005",
      exit_fee_splitter_address: "0x0000000000000000000000000000000000001006"
    )

    :ok
  end

  test "public status returns the TECH contract surface", %{conn: conn} do
    conn = get(conn, "/v1/tech/status")

    assert %{
             "data" => %{
               "contracts" => %{
                 "chain_id" => 8453,
                 "token" => "0x0000000000000000000000000000000000001001",
                 "reward_router" => "0x0000000000000000000000000000000000001002",
                 "exit_fee_splitter" => "0x0000000000000000000000000000000000001006"
               }
             }
           } = json_response(conn, 200)
  end

  test "proof and claim prepare use the stored manifest", %{conn: conn} do
    operator = agent!("operator", 9001)

    assert {:ok, _prepared} =
             Tech.prepare_reward_root(operator, %{
               "epoch" => 12,
               "lane" => "science",
               "total_budget_amount" => "25",
               "allocations" => [%{"agent_id" => "5", "score" => "1"}]
             })

    proof_conn =
      get(conn, "/v1/tech/rewards/proof", %{
        "epoch" => "12",
        "lane" => "science",
        "agent_id" => "5"
      })

    assert %{"data" => %{"agent_id" => "5", "amount" => "25", "proof" => []}} =
             json_response(proof_conn, 200)

    claim_conn =
      build_conn()
      |> with_siwa_headers(token_id: "5", wallet: wallet(5))
      |> post("/v1/agent/tech/rewards/claim/prepare", %{
        "epoch" => 12,
        "lane" => "science",
        "agent_id" => "5"
      })

    assert %{
             "data" => %{
               "transaction" => %{
                 "to" => "0x0000000000000000000000000000000000001002",
                 "function_signature" => "claim(uint64,uint8,uint256,uint256,bytes32,bytes32[])",
                 "args" => [12, 0, "5", "25", _, []]
               }
             }
           } = json_response(claim_conn, 200)
  end

  test "claim prepare requires signed-agent auth", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/v1/agent/tech/rewards/claim/prepare", %{})

    assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(conn, 401)
  end

  defp agent!(label, token_id) do
    Agents.upsert_verified_agent!(%{
      "chain_id" => 8453,
      "registry_address" => "0x0000000000000000000000000000000000009999",
      "token_id" => Integer.to_string(token_id),
      "wallet_address" => wallet(token_id),
      "label" => label
    })
  end

  defp wallet(seed) do
    "0x" <> String.pad_leading(Integer.to_string(seed, 16), 40, "0")
  end
end
