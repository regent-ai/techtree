defmodule TechTree.BenchmarksTest do
  use TechTree.DataCase, async: true

  alias TechTree.Agents
  alias TechTree.Benchmarks
  alias TechTree.Benchmarks.{Artifact, Capsule, CapsuleVersion}
  alias TechTree.NodeAccess.NodePaidPayload
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  describe "capsules and attempts" do
    test "creates a capsule, version, harness, attempt, and reliability summary" do
      agent = agent!("0x0000000000000000000000000000000000000001")

      {:ok, capsule} = Benchmarks.create_capsule(agent, capsule_attrs())

      {:ok, version} =
        Benchmarks.create_capsule_version(
          agent,
          capsule.capsule_id,
          version_attrs(%{
            "input_bundle_sha256" => "input-bundle-a",
            "version_status" => "published"
          })
        )

      {:ok, harness} =
        Benchmarks.create_harness(
          agent,
          harness_attrs(%{"normalized_bundle_hash" => "harness-bundle-a"})
        )

      for ordinal <- 1..5 do
        {:ok, _attempt} =
          Benchmarks.create_attempt(
            agent,
            attempt_attrs(version, harness, %{
              "attempt_ordinal" => ordinal,
              "repeat_group_id" => "repeat-a",
              "solved" => ordinal <= 4,
              "answer_hash" => if(ordinal <= 4, do: "answer-a", else: "answer-b"),
              "runtime_seconds" => 10 + ordinal,
              "cost_usd_micros" => 100 + ordinal
            })
          )
      end

      assert {:ok, [summary]} = Benchmarks.recompute_reliability(capsule.capsule_id)
      assert summary.attempt_count == 5
      assert summary.solve_count == 4
      assert summary.solve_rate == 0.8
      assert summary.reliable
      refute summary.brittle
      assert summary.answer_variance["unique_answer_count"] == 2
    end

    test "rejects attempts for retired versions" do
      agent = agent!("0x0000000000000000000000000000000000000002")

      {:ok, capsule} = Benchmarks.create_capsule(agent, capsule_attrs())

      {:ok, version} =
        Benchmarks.create_capsule_version(agent, capsule.capsule_id, version_attrs())

      {:ok, harness} = Benchmarks.create_harness(agent, harness_attrs())

      {:ok, retired} =
        Benchmarks.create_capsule_version(
          agent,
          capsule.capsule_id,
          version_attrs(%{"version_label" => "v2", "version_status" => "retired"})
        )

      assert {:error, :capsule_version_retired} =
               Benchmarks.create_attempt(agent, attempt_attrs(retired, harness))

      assert {:ok, _attempt} = Benchmarks.create_attempt(agent, attempt_attrs(version, harness))
    end

    test "rejects attempts with mismatched capsule, input bundle, or harness bundle" do
      agent = agent!("0x0000000000000000000000000000000000000003")

      {:ok, capsule} = Benchmarks.create_capsule(agent, capsule_attrs())

      {:ok, version} =
        Benchmarks.create_capsule_version(
          agent,
          capsule.capsule_id,
          version_attrs(%{"input_bundle_sha256" => "input-bundle-a"})
        )

      {:ok, harness} =
        Benchmarks.create_harness(
          agent,
          harness_attrs(%{"normalized_bundle_hash" => "harness-bundle-a"})
        )

      assert {:error, :capsule_version_mismatch} =
               Benchmarks.create_attempt(
                 agent,
                 attempt_attrs(version, harness, %{"capsule_id" => "bench_other"})
               )

      assert {:error, :input_bundle_sha256_mismatch} =
               Benchmarks.create_attempt(
                 agent,
                 attempt_attrs(version, harness, %{
                   "workspace_source" => %{"input_bundle_sha256" => "input-bundle-b"}
                 })
               )

      assert {:error, :harness_bundle_hash_mismatch} =
               Benchmarks.create_attempt(
                 agent,
                 attempt_attrs(version, harness, %{
                   "run_source" => %{"harness_bundle_hash" => "harness-bundle-b"}
                 })
               )
    end
  end

  describe "validations" do
    test "community validation cannot override an official rejection" do
      agent = agent!("0x0000000000000000000000000000000000000004")
      community_agent = agent!("0x0000000000000000000000000000000000000005")

      {:ok, capsule} = Benchmarks.create_capsule(agent, capsule_attrs())

      {:ok, version} =
        Benchmarks.create_capsule_version(agent, capsule.capsule_id, version_attrs())

      {:ok, harness} = Benchmarks.create_harness(agent, harness_attrs())
      {:ok, attempt} = Benchmarks.create_attempt(agent, attempt_attrs(version, harness))

      {:ok, _official} =
        Benchmarks.create_validation(
          agent,
          validation_attrs(attempt, %{"role" => "official", "result" => "rejected"})
        )

      {:ok, _community} =
        Benchmarks.create_validation(
          community_agent,
          validation_attrs(attempt, %{"role" => "community", "result" => "confirmed"})
        )

      assert {:ok, rejected_attempt} = Benchmarks.get_attempt(attempt.attempt_id)
      assert rejected_attempt.status == :rejected
      assert rejected_attempt.score_status == :rejected
      assert rejected_attempt.solved == false
    end
  end

  describe "public reads" do
    test "lists public capsules before applying the limit" do
      agent = agent!("0x0000000000000000000000000000000000000108")

      {:ok, public_capsule} =
        Benchmarks.create_capsule(
          agent,
          capsule_attrs(%{
            "title" => "Visible benchmark",
            "workflow_state" => "published",
            "visibility" => "public"
          })
        )

      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      _public_capsule = set_timestamps!(public_capsule, DateTime.add(now, -60, :second))

      for index <- 1..55 do
        {:ok, private_capsule} =
          Benchmarks.create_capsule(
            agent,
            capsule_attrs(%{
              "title" => "Private benchmark #{index}",
              "workflow_state" => "authoring",
              "visibility" => "draft"
            })
          )

        set_timestamps!(private_capsule, DateTime.add(now, index, :second))
      end

      assert [listed] = Benchmarks.list_public_capsules(%{"limit" => "1"})
      assert listed.capsule_id == public_capsule.capsule_id
    end

    test "public details hide non-public versions and artifacts" do
      agent = agent!("0x0000000000000000000000000000000000000109")

      {:ok, capsule} =
        Benchmarks.create_capsule(
          agent,
          capsule_attrs(%{
            "title" => "Filtered benchmark",
            "workflow_state" => "published",
            "visibility" => "public"
          })
        )

      {:ok, draft_version} =
        Benchmarks.create_capsule_version(
          agent,
          capsule.capsule_id,
          version_attrs(%{"version_label" => "draft", "version_status" => "draft"})
        )

      {:ok, published_version} =
        Benchmarks.create_capsule_version(
          agent,
          capsule.capsule_id,
          version_attrs(%{"version_label" => "v1", "version_status" => "published"})
        )

      {:ok, harness} = Benchmarks.create_harness(agent, harness_attrs())

      {:ok, draft_attempt} =
        Benchmarks.create_attempt(
          agent,
          attempt_attrs(draft_version, harness, %{"repeat_group_id" => "draft-repeat"})
        )

      {:ok, published_attempt} =
        Benchmarks.create_attempt(
          agent,
          attempt_attrs(published_version, harness, %{"repeat_group_id" => "published-repeat"})
        )

      assert {:ok, _summaries} = Benchmarks.recompute_reliability(capsule.capsule_id)

      assert {:error, :attempt_not_found} =
               Benchmarks.get_public_attempt(draft_attempt.attempt_id)

      assert {:ok, public_attempt} = Benchmarks.get_public_attempt(published_attempt.attempt_id)
      assert public_attempt.attempt_id == published_attempt.attempt_id

      _private_artifact =
        insert_artifact!(capsule, draft_version, %{
          "artifact_id" => "artifact_private_#{System.unique_integer([:positive])}",
          "kind" => "ground_truth_manifest",
          "name" => "Private review packet",
          "sha256" => "private-artifact-hash",
          "visibility" => "private"
        })

      _public_artifact_on_draft_version =
        insert_artifact!(capsule, draft_version, %{
          "artifact_id" => "artifact_draft_public_#{System.unique_integer([:positive])}",
          "kind" => "data_manifest",
          "name" => "Draft public artifact",
          "sha256" => "draft-public-artifact-hash",
          "visibility" => "public"
        })

      public_artifact =
        insert_artifact!(capsule, published_version, %{
          "artifact_id" => "artifact_public_#{System.unique_integer([:positive])}",
          "kind" => "data_manifest",
          "name" => "Public data manifest",
          "sha256" => "public-artifact-hash",
          "visibility" => "public"
        })

      assert {:ok, detail} = Benchmarks.public_detail_page(capsule.capsule_id)
      assert Enum.map(detail.versions, & &1.version_id) == [published_version.version_id]
      assert Enum.map(detail.artifacts, & &1.artifact_id) == [public_artifact.artifact_id]
      assert Enum.map(detail.reliability, & &1.version_id) == [published_version.version_id]

      assert Enum.map(detail.scoreboard.entries, & &1.version_id) == [
               published_version.version_id
             ]

      assert [listed] = Benchmarks.list_public_capsules(%{"limit" => "10"})

      assert Enum.map(listed.reliability_summaries, & &1.version_id) == [
               published_version.version_id
             ]

      assert Enum.map(Benchmarks.reliability_summaries(capsule.capsule_id), & &1.version_id) == [
               published_version.version_id
             ]

      assert Enum.map(Benchmarks.scoreboard(capsule.capsule_id).entries, & &1.version_id) == [
               published_version.version_id
             ]
    end
  end

  describe "agent publication actions" do
    test "marks capsules review-ready and publishes through node paid payloads" do
      agent = agent!("0x0000000000000000000000000000000000000006")
      parent = parent_node!(agent)

      {:ok, capsule} = Benchmarks.create_capsule(agent, capsule_attrs(%{"visibility" => "draft"}))

      {:ok, version} =
        Benchmarks.create_capsule_version(agent, capsule.capsule_id, version_attrs())

      assert {:ok, ready} =
               Benchmarks.mark_capsule_review_ready(agent, capsule.capsule_id, %{
                 "version_id" => version.version_id
               })

      assert ready.workflow_state == :review_ready
      assert ready.visibility == :private_review
      assert Repo.get!(CapsuleVersion, version.version_id).version_status == :review_ready

      assert {:ok, result} =
               Benchmarks.publish_capsule(agent, capsule.capsule_id, %{
                 "version_id" => version.version_id,
                 "seed" => "Benchmarks",
                 "parent_id" => parent.id,
                 "notebook_source" => "# Benchmark capsule\n",
                 "paid_payload" => %{
                   "encrypted_payload_uri" => "ipfs://bafy-benchmark-paid",
                   "encrypted_payload_cid" => "bafy-benchmark-paid",
                   "payload_hash" => "benchmark-paid-hash",
                   "seller_payout_address" => agent.wallet_address
                 }
               })

      assert result.capsule.workflow_state == :published
      assert result.capsule.visibility == :public
      assert result.capsule.source_node_id == result.publication_node.node_id
      assert result.version.version_status == :published
      assert result.version.publication_node_id == result.publication_node.node_id

      assert %NodePaidPayload{status: :draft, payload_hash: "benchmark-paid-hash"} =
               Repo.get_by(NodePaidPayload, node_id: result.publication_node.node_id)

      tx_hash = "0x" <> String.duplicate("a", 64)

      :ok =
        Benchmarks.sync_publication_anchor!(result.publication_node.node_id, %{
          tx_hash: tx_hash,
          chain_id: 8_453
        })

      anchored_version = Repo.get!(CapsuleVersion, version.version_id)
      assert anchored_version.chain_tx_hash == tx_hash
      assert anchored_version.chain_id == 8_453
      assert %DateTime{} = anchored_version.anchored_at
    end

    test "creates repeat groups with one shared group id" do
      agent = agent!("0x0000000000000000000000000000000000000007")

      {:ok, capsule} = Benchmarks.create_capsule(agent, capsule_attrs())

      {:ok, version} =
        Benchmarks.create_capsule_version(agent, capsule.capsule_id, version_attrs())

      {:ok, harness} = Benchmarks.create_harness(agent, harness_attrs())

      assert {:ok, result} =
               Benchmarks.create_repeat_group(agent, %{
                 "version_id" => version.version_id,
                 "harness_id" => harness.harness_id,
                 "repeat_group_id" => "repeat-contract-a",
                 "attempts" => [
                   %{"answer_hash" => "answer-a"},
                   %{"answer_hash" => "answer-a", "runtime_seconds" => 12},
                   %{"answer_hash" => "answer-b", "solved" => false}
                 ]
               })

      assert result.repeat_group_id == "repeat-contract-a"
      assert Enum.map(result.attempts, & &1.attempt_ordinal) == [1, 2, 3]
      assert Enum.all?(result.attempts, &(&1.repeat_group_id == "repeat-contract-a"))
      assert Enum.all?(result.attempts, &(&1.version_id == version.version_id))
      assert Enum.all?(result.attempts, &(&1.harness_id == harness.harness_id))
    end
  end

  defp agent!(wallet_address) do
    token_id = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => 8_453,
      "registry_address" => "0x0000000000000000000000000000000000009999",
      "token_id" => token_id,
      "wallet_address" => wallet_address,
      "label" => "benchmark-test-#{token_id}"
    })
  end

  defp parent_node!(agent) do
    unique = System.unique_integer([:positive])

    %Node{}
    |> Ecto.Changeset.change(%{
      path: "n#{unique}",
      depth: 0,
      seed: "ML",
      kind: :data,
      title: "Benchmark parent #{unique}",
      status: :anchored,
      notebook_source: "# parent",
      publish_idempotency_key: "benchmark-parent:#{unique}",
      creator_agent_id: agent.id
    })
    |> Repo.insert!()
  end

  defp capsule_attrs(extra \\ %{}) do
    Map.merge(
      %{
        "domain" => "bbh",
        "field" => "reasoning",
        "title" => "Benchmark capsule",
        "summary_md" => "A short benchmark capsule.",
        "question_md" => "What answer should the agent produce?",
        "difficulty_label" => "medium",
        "human_baseline_status" => "unknown",
        "ground_truth_policy" => "hidden_server",
        "answer_format" => %{"type" => "text"},
        "allowed_tools_policy" => %{"tools" => []},
        "external_resource_policy" => %{"allowed" => false},
        "scoring_policy" => %{"kind" => "exact"},
        "anti_cheat_policy" => %{"notes" => "No answer sharing."},
        "workflow_state" => "published",
        "visibility" => "public"
      },
      extra
    )
  end

  defp version_attrs(extra \\ %{}) do
    Map.merge(
      %{
        "version_label" => "v1",
        "version_status" => "published",
        "manifest_sha256" => "manifest-a",
        "input_bundle_sha256" => "input-bundle-a",
        "ground_truth_storage_policy" => %{"policy" => "hash_only"},
        "environment_lock_ref" => %{"kind" => "local"},
        "data_manifest" => %{"files" => []},
        "capsule_source" => %{"source" => "test"}
      },
      extra
    )
  end

  defp harness_attrs(extra \\ %{}) do
    Map.merge(
      %{
        "name" => "Test harness",
        "runner_kind" => "regents",
        "harness_version" => "2026-04-30",
        "prompt_pack_ref" => %{"sha256" => "prompt-a"},
        "skill_pack_refs" => [],
        "tool_profile" => %{"tools" => []},
        "dependency_lock_ref" => %{"sha256" => "deps-a"},
        "workspace_policy" => %{"network" => false},
        "normalized_bundle_hash" => "harness-bundle-a",
        "source" => %{"source" => "test"}
      },
      extra
    )
  end

  defp attempt_attrs(version, harness, extra \\ %{}) do
    Map.merge(
      %{
        "capsule_id" => version.capsule_id,
        "version_id" => version.version_id,
        "harness_id" => harness.harness_id,
        "repeat_group_id" => "repeat-#{System.unique_integer([:positive])}",
        "attempt_ordinal" => 1,
        "status" => "submitted",
        "score_status" => "scored",
        "raw_score" => 1.0,
        "normalized_score" => 1.0,
        "solved" => true,
        "answer_hash" => "answer-a",
        "verdict_json" => %{"verdict" => "ok"},
        "artifact_manifest" => %{"files" => []},
        "runtime_seconds" => 10,
        "cost_usd_micros" => 100,
        "run_source" => %{"harness_bundle_hash" => harness.normalized_bundle_hash},
        "workspace_source" => %{"input_bundle_sha256" => version.input_bundle_sha256}
      },
      extra
    )
  end

  defp validation_attrs(attempt, extra) do
    Map.merge(
      %{
        "attempt_id" => attempt.attempt_id,
        "capsule_id" => attempt.capsule_id,
        "role" => "community",
        "method" => "replay",
        "result" => "confirmed",
        "summary_md" => "The result was reviewed.",
        "verdict_json" => %{"review" => "ok"},
        "review_source" => %{"source" => "test"}
      },
      extra
    )
  end

  defp set_timestamps!(%Capsule{} = capsule, datetime) do
    capsule
    |> Ecto.Changeset.change(inserted_at: datetime, updated_at: datetime)
    |> Repo.update!()
  end

  defp insert_artifact!(capsule, version, attrs) do
    attrs =
      Map.merge(
        %{
          "capsule_id" => capsule.capsule_id,
          "version_id" => version.version_id,
          "storage_provider" => "techtree",
          "encryption_meta" => %{}
        },
        attrs
      )

    %Artifact{}
    |> Artifact.changeset(attrs)
    |> Repo.insert!()
  end
end
