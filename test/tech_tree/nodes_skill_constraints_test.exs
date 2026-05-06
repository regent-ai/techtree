defmodule TechTree.NodesSkillConstraintsTest do
  use TechTree.DataCase, async: true

  alias TechTree.Agents
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  describe "nodes_skill_fields_check" do
    test "rejects skill node with nil skill_md_body" do
      creator = create_agent!("skill-constraint")
      unique = System.unique_integer([:positive])

      assert_raise Ecto.ConstraintError, ~r/nodes_skill_fields_check/, fn ->
        %Node{}
        |> Ecto.Changeset.change(%{
          path: "n#{unique}",
          depth: 0,
          seed: "Skills",
          kind: :skill,
          title: "skill-#{unique}",
          status: :pinned,
          notebook_source: "print('skill')",
          publish_idempotency_key: "skill-constraint:#{unique}",
          creator_agent_id: creator.id,
          skill_slug: "skill-#{unique}",
          skill_version: "1.0.0",
          skill_md_body: nil
        })
        |> Repo.insert!()
      end
    end

    test "rejects non-skill node carrying skill fields" do
      creator = create_agent!("nonskill-constraint")
      unique = System.unique_integer([:positive])

      assert_raise Ecto.ConstraintError, ~r/nodes_skill_fields_check/, fn ->
        %Node{}
        |> Ecto.Changeset.change(%{
          path: "n#{unique}",
          depth: 0,
          seed: "ML",
          kind: :hypothesis,
          title: "hypothesis-#{unique}",
          status: :pinned,
          notebook_source: "print('hypothesis')",
          publish_idempotency_key: "nonskill-constraint:#{unique}",
          creator_agent_id: creator.id,
          skill_slug: "should-not-be-set",
          skill_version: "1.0.0",
          skill_md_body: "# invalid"
        })
        |> Repo.insert!()
      end
    end
  end

  defp create_agent!(label_prefix) do
    unique = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => "8453",
      "registry_address" => random_eth_address(),
      "token_id" => Integer.to_string(unique),
      "wallet_address" => random_eth_address(),
      "label" => "#{label_prefix}-#{unique}"
    })
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end
end
