defmodule TechTree.PhaseDSecurityPerfTest do
  use TechTree.DataCase, async: false

  alias Oban.Job
  alias TechTree.Agents
  alias TechTree.RateLimit
  alias TechTree.Accounts.HumanUser
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  alias TechTree.Workers.{
    AnchorNodeWorker,
    AwaitNodeReceiptWorker
  }

  alias TechTree.XMTPMirror
  alias TechTree.XMTPMirror.XmtpMembershipCommand

  describe "rate-limit abuse windows" do
    test "node/comment keys block replays and isolate by wallet+node when dragonfly is available" do
      wallet_a = "0xphaseDwalletA#{System.unique_integer([:positive])}"
      wallet_b = "0xphaseDwalletB#{System.unique_integer([:positive])}"
      node_a = System.unique_integer([:positive])
      node_b = node_a + 1

      if dragonfly_available?() do
        assert :ok = RateLimit.check_node_create!(wallet_a)
        assert {:error, :rate_limited} = RateLimit.check_node_create!(wallet_a)

        assert :ok = RateLimit.check_node_create!(wallet_b)

        assert :ok = RateLimit.check_comment_create!(wallet_a, node_a)
        assert {:error, :rate_limited} = RateLimit.check_comment_create!(wallet_a, node_a)

        assert :ok = RateLimit.check_comment_create!(wallet_a, node_b)
        assert :ok = RateLimit.check_comment_create!(wallet_b, node_a)
      else
        # Fail-closed fallback when dragonfly is unavailable in the execution environment.
        assert {:error, :rate_limited} = RateLimit.check_node_create!(wallet_a)
        assert {:error, :rate_limited} = RateLimit.check_comment_create!(wallet_a, node_a)
      end
    end

    test "chatbox burst limiter blocks the 11th post inside the rolling window" do
      identity = "phase-d-chatbox-#{System.unique_integer([:positive])}"
      post_key = "rl:chatbox:post:#{identity}"
      burst_key = "rl:chatbox:burst:#{identity}"

      if dragonfly_available?() do
        assert {:ok, _} = Redix.command(:dragonfly, ["DEL", post_key, burst_key])

        Enum.each(1..10, fn _attempt ->
          assert :ok = RateLimit.check_chatbox_post!(identity)

          # Simulate elapsed per-post cooldown without sleeping to exercise burst-window logic.
          assert {:ok, _} = Redix.command(:dragonfly, ["DEL", post_key])
        end)

        assert {:error, :rate_limited} = RateLimit.check_chatbox_post!(identity)

        # Simulate burst window expiry to validate recovery.
        assert {:ok, _} = Redix.command(:dragonfly, ["DEL", post_key, burst_key])
        assert :ok = RateLimit.check_chatbox_post!(identity)
      else
        assert {:error, :rate_limited} = RateLimit.check_chatbox_post!(identity)
      end
    end
  end

  describe "queue failure and retry paths" do
    test "AnchorNodeWorker returns error on missing manifest payload and succeeds on corrected retry" do
      creator = create_agent!("anchor-retry")

      node =
        create_node!(creator, %{
          status: :pinned,
          manifest_uri: "ipfs://phase-d-anchor-manifest",
          manifest_hash: nil
        })

      args = %{"node_id" => node.id, "idempotency_key" => node.publish_idempotency_key}

      assert {:error, %ArgumentError{}} = AnchorNodeWorker.perform(%Job{args: args})
      assert count_jobs(AwaitNodeReceiptWorker, node.id) == 0

      _ =
        node
        |> Ecto.Changeset.change(manifest_hash: "phase-d-anchor-hash")
        |> Repo.update!()

      assert :ok = AnchorNodeWorker.perform(%Job{args: args})
      assert count_jobs(AwaitNodeReceiptWorker, node.id) == 1
    end

    test "membership command failure can be retried without duplicate in-flight queueing" do
      {:ok, _room} =
        XMTPMirror.ensure_room(%{
          room_key: "public-chatbox",
          xmtp_group_id: "phase-d-group-#{System.unique_integer([:positive])}",
          name: "Public Chatbox",
          status: "active"
        })

      {:ok, human} =
        %HumanUser{}
        |> HumanUser.changeset(%{
          privy_user_id: "phase-d-privy-#{System.unique_integer([:positive])}",
          wallet_address: "0xphaseDhuman#{System.unique_integer([:positive])}",
          xmtp_inbox_id: "phase-d-inbox-#{System.unique_integer([:positive])}",
          display_name: "phase-d-human"
        })
        |> Repo.insert()

      assert {:ok, %{status: "pending"}} = XMTPMirror.request_join(human)

      leased_1 = XMTPMirror.lease_next_command("public-chatbox")
      assert leased_1.status == "processing"
      assert leased_1.attempt_count == 1

      assert :ok =
               XMTPMirror.resolve_command(leased_1.id, %{
                 "status" => "failed",
                 "error" => "simulated transport timeout"
               })

      failed_1 = Repo.get!(XmtpMembershipCommand, leased_1.id)
      assert failed_1.status == "failed"

      assert {:ok, %{status: "pending"}} = XMTPMirror.request_join(human)
      leased_2 = XMTPMirror.lease_next_command("public-chatbox")
      assert leased_2.id != leased_1.id
      assert leased_2.status == "processing"
      assert leased_2.attempt_count == 1

      assert {:ok, %{status: "pending"}} = XMTPMirror.request_join(human)
      assert count_membership_commands(human.id, "add_member") == 2
    end
  end

  describe "database integrity hardening" do
    test "rejects non-seed roots without a parent at the database layer" do
      creator = create_agent!("constraint-parent")
      unique = System.unique_integer([:positive])

      assert_raise Ecto.ConstraintError, ~r/nodes_non_seed_parent_required_check/, fn ->
        %Node{}
        |> Ecto.Changeset.change(%{
          path: "n#{unique}",
          depth: 0,
          seed: "NotASeedRoot",
          kind: :hypothesis,
          title: "invalid-root-#{unique}",
          status: :pinned,
          notebook_source: "print('invalid root')",
          publish_idempotency_key: "constraint-parent:#{unique}",
          parent_id: nil,
          creator_agent_id: creator.id
        })
        |> Repo.insert!()
      end
    end

    test "rejects non-skill nodes carrying skill fields at the database layer" do
      creator = create_agent!("constraint-skill")
      unique = System.unique_integer([:positive])

      assert_raise Ecto.ConstraintError, ~r/nodes_skill_fields_check/, fn ->
        %Node{}
        |> Ecto.Changeset.change(%{
          path: "n#{unique}",
          depth: 0,
          seed: "ML",
          kind: :hypothesis,
          title: "invalid-skill-fields-#{unique}",
          status: :pinned,
          notebook_source: "print('invalid skill fields')",
          publish_idempotency_key: "constraint-skill:#{unique}",
          creator_agent_id: creator.id,
          skill_slug: "should-not-exist",
          skill_version: "1.0.0",
          skill_md_body: "# invalid"
        })
        |> Repo.insert!()
      end
    end

    test "rejects skill nodes missing required skill payload fields" do
      creator = create_agent!("constraint-skill-required")
      unique = System.unique_integer([:positive])

      assert_raise Ecto.ConstraintError, ~r/nodes_skill_fields_check/, fn ->
        %Node{}
        |> Ecto.Changeset.change(%{
          path: "n#{unique}",
          depth: 0,
          seed: "ML",
          kind: :skill,
          title: "invalid-skill-node-#{unique}",
          status: :pinned,
          notebook_source: "print('invalid skill node')",
          publish_idempotency_key: "constraint-skill-required:#{unique}",
          creator_agent_id: creator.id,
          skill_slug: "skill-#{unique}",
          skill_version: nil,
          skill_md_body: "# missing version"
        })
        |> Repo.insert!()
      end
    end
  end

  defp dragonfly_available? do
    match?({:ok, "PONG"}, Redix.command(:dragonfly, ["PING"]))
  end

  defp create_agent!(label_prefix) do
    unique = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => "11155111",
      "registry_address" => random_eth_address(),
      "token_id" => Integer.to_string(unique),
      "wallet_address" => random_eth_address(),
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
      title: "phase-d-node-#{unique}",
      status: :pinned,
      notebook_source: "print('phase_d')",
      publish_idempotency_key: "phase-d-node:#{unique}",
      creator_agent_id: creator.id
    }

    %Node{}
    |> Ecto.Changeset.change(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end

  defp count_jobs(worker_module, node_id) do
    worker_name = worker_module |> Module.split() |> Enum.join(".")

    Job
    |> where([j], j.worker == ^worker_name)
    |> where([j], fragment("? ->> 'node_id' = ?", j.args, ^to_string(node_id)))
    |> Repo.aggregate(:count, :id)
  end

  defp count_membership_commands(human_id, op) do
    XmtpMembershipCommand
    |> where([c], c.human_user_id == ^human_id and c.op == ^op)
    |> Repo.aggregate(:count, :id)
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end
end
