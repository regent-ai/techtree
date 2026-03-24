defmodule TechTree.V1Fixtures do
  @moduledoc false

  alias TechTree.Repo
  alias TechTree.V1.{Artifact, Node, Review, Run}

  def insert_bbh_bundle!(attrs \\ %{}) do
    suffix = unique_suffix()
    artifact_id = Map.get(attrs, :artifact_id, bytes32("a1", suffix))
    run_id = Map.get(attrs, :run_id, bytes32("b2", suffix))
    review_id = Map.get(attrs, :review_id, bytes32("c3", suffix))
    split = Map.get(attrs, :split, "benchmark")
    display_name = Map.get(attrs, :display_name, "Canonical Genome")
    fingerprint = Map.get(attrs, :fingerprint, "fingerprint-#{suffix}")
    score = Map.get(attrs, :score, 84.0)

    artifact_node =
      Repo.insert!(%Node{
        id: artifact_id,
        node_type: 1,
        author: zero_address(),
        subject_id: artifact_id,
        aux_id: artifact_id,
        payload_hash: sha(),
        schema_version: 1,
        verification_status: "verified",
        header: %{"id" => artifact_id},
        manifest: %{
          "title" => Map.get(attrs, :artifact_title, "BBH Capsule"),
          "summary" => Map.get(attrs, :artifact_summary, "Canonical BBH artifact"),
          "eval" => %{
            "instance" => %{"params" => %{"tree" => "bbh", "split" => split}}
          }
        },
        payload_index: %{}
      })

    artifact =
      Repo.insert!(%Artifact{
        id: artifact_id,
        kind: "capsule",
        title: Map.get(attrs, :artifact_title, "BBH Capsule"),
        summary: Map.get(attrs, :artifact_summary, "Canonical BBH artifact"),
        has_eval: true,
        eval_mode: "fixed"
      })

    run_node =
      Repo.insert!(%Node{
        id: run_id,
        node_type: 2,
        author: zero_address(),
        subject_id: run_id,
        aux_id: artifact_id,
        payload_hash: sha(),
        schema_version: 1,
        verification_status: "verified",
        header: %{"id" => run_id},
        manifest: %{
          "artifact_id" => artifact_id,
          "executor" => %{
            "type" => "genome",
            "id" => "genome:#{display_name}",
            "harness" => %{
              "kind" => Map.get(attrs, :executor_harness_kind, "hermes"),
              "profile" => Map.get(attrs, :executor_harness_profile, "bbh")
            }
          },
          "instance" => %{
            "instance_id" => "bbh-run",
            "params" => %{
              "tree" => "bbh",
              "split" => split,
              "genome" => %{
                "display_name" => display_name,
                "fingerprint" => fingerprint,
                "model" => "gpt-test",
                "router" => "router-test",
                "planner" => nil,
                "critic" => nil,
                "tool_policy" => "balanced",
                "runtime" => "regent"
              }
            }
          },
          "origin" => %{
            "kind" => Map.get(attrs, :origin_kind, "local"),
            "transport" => Map.get(attrs, :origin_transport),
            "session_id" => Map.get(attrs, :origin_session_id, "session-#{suffix}")
          },
          "env_observed" => %{
            "python" => "3.11",
            "platform" => "linux/amd64",
            "image" => "ghcr.io/regent/bbh:test"
          },
          "outputs" => %{
            "primary_output" => "outputs/verdict.json",
            "verdict_ref" => "outputs/verdict.json",
            "log_ref" => "logs/run.log"
          },
          "run_provenance" => %{"runner_id" => "regent-test"}
        },
        payload_index: %{}
      })

    run =
      Repo.insert!(
        struct(Run, %{
          id: run_id,
          artifact_id: artifact_id,
          executor_type: "genome",
          executor_id: "genome:#{display_name}",
          executor_harness_kind: Map.get(attrs, :executor_harness_kind, "hermes"),
          executor_harness_profile: Map.get(attrs, :executor_harness_profile, "bbh"),
          origin_kind: Map.get(attrs, :origin_kind, "local"),
          origin_transport: Map.get(attrs, :origin_transport),
          origin_session_id: Map.get(attrs, :origin_session_id, "session-#{suffix}"),
          status: "completed",
          score: score
        })
      )

    review_node =
      Repo.insert!(%Node{
        id: review_id,
        node_type: 3,
        author: zero_address(),
        subject_id: review_id,
        aux_id: run_id,
        payload_hash: sha(),
        schema_version: 1,
        verification_status: "verified",
        header: %{"id" => review_id},
        manifest: %{
          "target" => %{"type" => "run", "id" => run_id},
          "kind" => "validation",
          "method" => "replay",
          "result" => Map.get(attrs, :review_result, "confirmed"),
          "summary" => "Canonical replay review"
        },
        payload_index: %{}
      })

    review =
      Repo.insert!(%Review{
        id: review_id,
        target_type: "run",
        target_id: run_id,
        kind: "validation",
        method: "replay",
        result: Map.get(attrs, :review_result, "confirmed"),
        scope_level: "whole",
        scope_path: nil
      })

    %{
      artifact_node: artifact_node,
      artifact: artifact,
      run_node: run_node,
      run: run,
      review_node: review_node,
      review: review
    }
  end

  defp unique_suffix do
    System.unique_integer([:positive])
    |> Integer.to_string(16)
    |> String.pad_leading(62, "0")
  end

  defp bytes32(prefix, suffix) do
    "0x" <> prefix <> suffix
  end

  defp sha do
    "sha256:" <> String.duplicate("1", 64)
  end

  defp zero_address do
    "0x0000000000000000000000000000000000000000"
  end
end
