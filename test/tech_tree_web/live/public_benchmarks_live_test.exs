defmodule TechTreeWeb.PublicBenchmarksLiveTest do
  use TechTreeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TechTree.Agents
  alias TechTree.Benchmarks

  test "benchmark hub renders public capsules", %{conn: conn} do
    %{capsule: capsule} = create_public_benchmark!("hub")

    {:ok, view, _html} = live(conn, ~p"/benchmarks")

    assert has_element?(view, "#benchmarks-page")
    assert render(view) =~ capsule.title
    assert render(view) =~ "Benchmark capsules"
    refute_internal_copy(render(view))
  end

  test "benchmark detail renders evidence without hidden answers", %{conn: conn} do
    %{capsule: capsule, version: version, harness: harness} = create_public_benchmark!("detail")

    {:ok, attempt} =
      Benchmarks.create_attempt(
        agent!("0x0000000000000000000000000000000000000101"),
        %{
          "capsule_id" => capsule.capsule_id,
          "version_id" => version.version_id,
          "harness_id" => harness.harness_id,
          "repeat_group_id" => "detail-repeat",
          "attempt_ordinal" => 1,
          "status" => "submitted",
          "score_status" => "scored",
          "solved" => true,
          "answer_hash" => "public-answer-fingerprint",
          "artifact_manifest" => %{},
          "verdict_json" => %{},
          "run_source" => %{"harness_bundle_hash" => harness.normalized_bundle_hash},
          "workspace_source" => %{"input_bundle_sha256" => version.input_bundle_sha256}
        }
      )

    {:ok, _validation} =
      Benchmarks.create_validation(
        agent!("0x0000000000000000000000000000000000000102"),
        %{
          "attempt_id" => attempt.attempt_id,
          "capsule_id" => capsule.capsule_id,
          "role" => "community",
          "method" => "replay",
          "result" => "confirmed",
          "summary_md" => "The result was reviewed.",
          "verdict_json" => %{},
          "review_source" => %{}
        }
      )

    {:ok, [_summary]} = Benchmarks.recompute_reliability(capsule.capsule_id)

    {:ok, view, _html} = live(conn, ~p"/benchmarks/#{capsule.capsule_id}")

    html = render(view)
    assert html =~ capsule.title
    assert html =~ "Reliability"
    assert html =~ "Evidence"
    refute html =~ "hidden truth"
    refute_internal_copy(html)
  end

  defp create_public_benchmark!(label) do
    owner =
      agent!(
        "0x000000000000000000000000000000000000#{String.pad_leading(label_suffix(label), 4, "0")}"
      )

    {:ok, capsule} =
      Benchmarks.create_capsule(owner, %{
        "domain" => "bbh",
        "field" => "reasoning",
        "title" => "Public #{label} benchmark",
        "summary_md" => "A public benchmark capsule.",
        "question_md" => "Solve the public prompt.",
        "difficulty_label" => "medium",
        "human_baseline_status" => "unknown",
        "ground_truth_policy" => "hidden_server",
        "answer_format" => %{"type" => "text"},
        "allowed_tools_policy" => %{},
        "external_resource_policy" => %{},
        "scoring_policy" => %{},
        "anti_cheat_policy" => %{},
        "workflow_state" => "published",
        "visibility" => "public"
      })

    {:ok, version} =
      Benchmarks.create_capsule_version(owner, capsule.capsule_id, %{
        "version_label" => "v1",
        "version_status" => "published",
        "manifest_sha256" => "manifest-#{label}",
        "input_bundle_sha256" => "input-#{label}",
        "ground_truth_storage_policy" => %{"policy" => "hash_only"},
        "environment_lock_ref" => %{},
        "data_manifest" => %{},
        "capsule_source" => %{}
      })

    {:ok, harness} =
      Benchmarks.create_harness(owner, %{
        "name" => "Public #{label} harness",
        "runner_kind" => "regents",
        "harness_version" => "v1",
        "prompt_pack_ref" => %{},
        "skill_pack_refs" => [],
        "tool_profile" => %{},
        "dependency_lock_ref" => %{},
        "workspace_policy" => %{},
        "normalized_bundle_hash" => "harness-#{label}",
        "source" => %{}
      })

    %{capsule: capsule, version: version, harness: harness}
  end

  defp agent!(wallet_address) do
    unique = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => "8453",
      "registry_address" => "0x0000000000000000000000000000000000008888",
      "token_id" => Integer.to_string(unique),
      "wallet_address" => wallet_address,
      "label" => "public-benchmark-#{unique}"
    })
  end

  defp label_suffix(label) do
    label
    |> :erlang.phash2(10_000)
    |> Integer.to_string()
  end

  defp refute_internal_copy(html) do
    text = visible_text(html)

    refute text =~ "LiveView"
    refute text =~ "fallback"
    refute text =~ "hook"
    refute text =~ "server-rendered"
    refute text =~ "state management"
  end

  defp visible_text(html) do
    Regex.replace(~r/<[^>]+>/, html, " ")
  end
end
