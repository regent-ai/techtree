defmodule TechTree.TechTest do
  use TechTree.DataCase, async: true

  alias TechTree.Agents
  alias TechTree.Repo
  alias TechTree.Tech
  alias TechTree.Tech.{RewardAllocation, RewardEpoch}

  setup do
    Application.put_env(:tech_tree, :tech,
      chain_id: 8453,
      token_address: "0x0000000000000000000000000000000000001001",
      reward_router_address: "0x0000000000000000000000000000000000001002",
      agent_reward_vault_address: "0x0000000000000000000000000000000000001003",
      emission_controller_address: "0x0000000000000000000000000000000000001004",
      leaderboard_registry_address: "0x0000000000000000000000000000000000001005",
      exit_swap_address: "0x0000000000000000000000000000000000001006"
    )

    :ok
  end

  test "builds deterministic science reward buckets and proofs" do
    operator = agent!("operator", 999)

    rows =
      for rank <- 1..60 do
        %{
          "agent_id" => Integer.to_string(rank),
          "wallet_address" => wallet(rank),
          "score" => Integer.to_string(1_000 - rank),
          "leaderboard_id" => "bbh"
        }
      end

    assert {:ok, %{manifest: manifest, transaction: tx}} =
             Tech.prepare_reward_root(operator, %{
               "epoch" => 7,
               "lane" => "science",
               "total_budget_amount" => "1000",
               "leaderboard_ids" => ["bbh"],
               "allocations" => rows
             })

    assert manifest.total_allocated_amount == "1000"
    assert manifest.allocation_count == 60
    assert tx.to == "0x0000000000000000000000000000000000001002"

    assert tx.function_signature ==
             "postAllocationRoot(uint64,uint8,bytes32,uint256,bytes32,uint64)"

    assert [7, 0, manifest.merkle_root, "1000", manifest.manifest_hash, 0] == tx.args

    allocations =
      RewardAllocation
      |> Repo.all()
      |> Enum.sort_by(& &1.rank)

    assert allocations |> Enum.take(12) |> sum_amounts() == 750
    assert allocations |> Enum.slice(12, 38) |> sum_amounts() == 200
    assert allocations |> Enum.slice(50, 10) |> sum_amounts() == 50

    assert {:ok, proof} =
             Tech.reward_proof(%{"epoch" => 7, "lane" => "science", "agent_id" => "1"})

    assert proof.merkle_root == manifest.merkle_root
    assert proof.proof != []
  end

  test "claim prepare only works for the signed agent id" do
    operator = agent!("operator", 1000)
    claimant = agent!("claimant", 1)

    assert {:ok, _prepared} =
             Tech.prepare_reward_root(operator, %{
               "epoch" => 8,
               "lane" => "science",
               "total_budget_amount" => "10",
               "allocations" => [%{"agent_id" => "1", "score" => "1"}]
             })

    assert {:ok, %{transaction: tx, proof: proof}} =
             Tech.prepare_reward_claim(claimant, %{
               "epoch" => 8,
               "lane" => "science",
               "agent_id" => "1"
             })

    assert tx.to == "0x0000000000000000000000000000000000001002"
    assert [8, 0, "1", "10", proof.allocation_ref, []] == tx.args

    assert {:error, :agent_id_mismatch} =
             Tech.prepare_reward_claim(claimant, %{
               "epoch" => 8,
               "lane" => "science",
               "agent_id" => "2"
             })
  end

  test "epoch summaries preserve both reward lanes" do
    operator = agent!("operator", 1001)

    assert {:ok, _prepared} =
             Tech.prepare_reward_root(operator, %{
               "epoch" => 9,
               "lane" => "science",
               "total_budget_amount" => "75",
               "allocations" => [%{"agent_id" => "1", "score" => "10"}]
             })

    assert {:ok, _prepared} =
             Tech.prepare_reward_root(operator, %{
               "epoch" => 9,
               "lane" => "usdc_input",
               "total_budget_amount" => "25",
               "allocations" => [%{"agent_id" => "2", "score" => "5"}]
             })

    epoch = Repo.get!(RewardEpoch, 9)
    assert epoch.science_budget_amount == "75"
    assert epoch.input_budget_amount == "25"
    assert epoch.total_emission_amount == "100"
  end

  test "withdraw prepare requires a nonzero REGENT minimum" do
    agent = agent!("withdrawer", 42)

    attrs = %{
      "agent_id" => "42",
      "amount" => "1000000000000000000",
      "tech_recipient" => "0x0000000000000000000000000000000000000042",
      "regent_recipient" => "0x0000000000000000000000000000000000000043",
      "min_regent_out" => "1",
      "deadline" => 1_900_000_000
    }

    assert {:ok, %{transaction: tx, withdrawal: withdrawal}} =
             Tech.prepare_withdrawal(agent, attrs)

    assert withdrawal.status == "prepared"
    assert tx.to == "0x0000000000000000000000000000000000001003"
    assert tx.function_signature == "withdraw(uint256,uint256,address,address,uint256,uint256)"
    assert ["42", "1000000000000000000", _, _, "1", 1_900_000_000] = tx.args

    assert {:error, :amount_zero} =
             Tech.prepare_withdrawal(agent, %{attrs | "min_regent_out" => "0"})
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

  defp sum_amounts(allocations) do
    Enum.reduce(allocations, 0, fn allocation, acc ->
      acc + String.to_integer(allocation.amount)
    end)
  end
end
