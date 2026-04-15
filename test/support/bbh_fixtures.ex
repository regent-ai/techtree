defmodule TechTree.BBHFixtures do
  @moduledoc false

  alias TechTree.BBH.{
    Assignment,
    Capsule,
    DraftProposal,
    Genome,
    OrcidLinkRequest,
    ReviewRequest,
    ReviewSubmission,
    ReviewerProfile,
    Run,
    Validation
  }

  alias TechTree.Repo

  def insert_capsule!(attrs \\ %{}) do
    suffix = suffix()

    defaults = %{
      capsule_id: "capsule_#{suffix}",
      provider: "bbh_train",
      provider_ref: "provider/#{suffix}",
      family_ref: nil,
      instance_ref: "instance_#{suffix}",
      split: "climb",
      language: "python",
      mode: "fixed",
      assignment_policy: "auto_or_select",
      title: "Capsule #{suffix}",
      hypothesis: "The treatment should improve the signal.",
      protocol_md: "1. Read the data\n2. Score the hypothesis\n",
      rubric_json: %{"items" => [%{"id" => "final_objective", "points" => 5}]},
      task_json: %{
        "capsule_id" => "capsule_#{suffix}",
        "hypothesis" => "The treatment should improve the signal."
      },
      workflow_state: "authoring",
      notebook_py: "print('capsule')\n",
      capsule_source: %{"schema_version" => "techtree.bbh.capsule-source.v1"},
      recommended_genome_source: %{"schema_version" => "techtree.bbh.genome-source.v1"},
      genome_notes_md: "",
      certificate_status: "none",
      data_files: [%{"name" => "input.csv", "content" => "x,y\n1,2\n"}],
      artifact_source: %{"schema_version" => "techtree.bbh.artifact-source.v1"}
    }

    attrs = Map.merge(defaults, attrs)

    %Capsule{}
    |> Capsule.changeset(attrs)
    |> Repo.insert!()
  end

  def insert_assignment!(%Capsule{} = capsule, attrs \\ %{}) do
    defaults = %{
      assignment_ref: "asg_#{suffix()}",
      capsule_id: capsule.capsule_id,
      split: capsule.split,
      status: "assigned",
      agent_wallet_address: random_eth_address(),
      agent_token_id: Integer.to_string(System.unique_integer([:positive])),
      origin: capsule.assignment_policy
    }

    %Assignment{}
    |> Assignment.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_reviewer_profile!(attrs \\ %{}) do
    defaults = %{
      wallet_address: Map.get(attrs, :wallet_address, random_eth_address()),
      orcid_id: Map.get(attrs, :orcid_id, "0000-0000-0000-0001"),
      orcid_auth_kind: Map.get(attrs, :orcid_auth_kind, "oauth_authenticated"),
      orcid_name: Map.get(attrs, :orcid_name, "Reviewer"),
      vetting_status: Map.get(attrs, :vetting_status, "approved"),
      domain_tags: Map.get(attrs, :domain_tags, ["scrna-seq"]),
      payout_wallet: Map.get(attrs, :payout_wallet, random_eth_address())
    }

    %ReviewerProfile{}
    |> ReviewerProfile.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_orcid_link_request!(attrs \\ %{}) do
    defaults = %{
      request_id: "orcid_req_#{suffix()}",
      wallet_address: Map.get(attrs, :wallet_address, random_eth_address()),
      state: Map.get(attrs, :state, "pending"),
      expires_at: Map.get(attrs, :expires_at, DateTime.add(DateTime.utc_now(), 600, :second))
    }

    %OrcidLinkRequest{}
    |> OrcidLinkRequest.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_review_request!(%Capsule{} = capsule, attrs \\ %{}) do
    defaults = %{
      request_id: "review_req_#{suffix()}",
      capsule_id: capsule.capsule_id,
      review_kind: Map.get(attrs, :review_kind, "certification"),
      visibility: Map.get(attrs, :visibility, "public_claim"),
      state: Map.get(attrs, :state, "open"),
      claimed_by_wallet: Map.get(attrs, :claimed_by_wallet),
      fee_quote_usdc: Map.get(attrs, :fee_quote_usdc),
      holdback_usdc: Map.get(attrs, :holdback_usdc),
      due_at: Map.get(attrs, :due_at)
    }

    %ReviewRequest{}
    |> ReviewRequest.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_draft_proposal!(%Capsule{} = capsule, attrs \\ %{}) do
    defaults = %{
      proposal_id: "proposal_#{suffix()}",
      capsule_id: capsule.capsule_id,
      proposer_wallet_address: Map.get(attrs, :proposer_wallet_address, random_eth_address()),
      summary: Map.get(attrs, :summary, "Tightened protocol"),
      workspace_bundle:
        Map.get(attrs, :workspace_bundle, %{
          "notebook_py" => "print('proposal')\n",
          "hypothesis_md" => capsule.hypothesis,
          "protocol_md" => capsule.protocol_md,
          "rubric_json" => capsule.rubric_json,
          "capsule_source" => capsule.capsule_source,
          "recommended_genome_source" => capsule.recommended_genome_source,
          "genome_notes_md" => capsule.genome_notes_md
        }),
      patch_json: Map.get(attrs, :patch_json, %{}),
      workspace_manifest_hash:
        Map.get(attrs, :workspace_manifest_hash, "sha256:#{String.duplicate("1", 64)}"),
      status: Map.get(attrs, :status, "open")
    }

    %DraftProposal{}
    |> DraftProposal.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_review_submission!(%ReviewRequest{} = request, attrs \\ %{}) do
    defaults = %{
      submission_id: "review_sub_#{suffix()}",
      request_id: request.request_id,
      capsule_id: request.capsule_id,
      reviewer_wallet: Map.get(attrs, :reviewer_wallet, random_eth_address()),
      checklist_json: Map.get(attrs, :checklist_json, %{"decision" => "approve"}),
      suggested_edits_json: Map.get(attrs, :suggested_edits_json, %{"edits" => []}),
      decision: Map.get(attrs, :decision, "approve"),
      summary_md: Map.get(attrs, :summary_md, "Looks good."),
      genome_recommendation_source: Map.get(attrs, :genome_recommendation_source, %{}),
      certificate_payload: Map.get(attrs, :certificate_payload, %{}),
      review_node_id: Map.get(attrs, :review_node_id)
    }

    %ReviewSubmission{}
    |> ReviewSubmission.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_genome!(attrs \\ %{}) do
    suffix = suffix()
    source = genome_source(Map.take(attrs, [:genome_id, :label, :model_id, :harness_type]))
    genome_id = Map.get(attrs, :genome_id, source["genome_id"])
    bundle_hash = normalized_bundle_hash(source)

    defaults = %{
      genome_id: genome_id,
      label: Map.get(attrs, :label, "Genome #{suffix}"),
      parent_genome_ref: nil,
      model_id: Map.get(attrs, :model_id, "gpt-test"),
      harness_type: Map.get(attrs, :harness_type, "hermes"),
      harness_version: "1.0.0",
      prompt_pack_version: "bbh-v0.1",
      skill_pack_version: "techtree-bbh-v0.1",
      tool_profile: "bbh",
      runtime_image: "local-runtime",
      helper_code_hash: nil,
      data_profile: "python-only",
      axes: %{},
      notes: nil,
      normalized_bundle_hash: bundle_hash,
      source: source
    }

    attrs = Map.merge(defaults, attrs)

    %Genome{}
    |> Genome.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, genome} ->
        genome

      {:error, changeset} ->
        if Keyword.has_key?(changeset.errors, :normalized_bundle_hash) do
          Repo.get_by!(Genome, normalized_bundle_hash: bundle_hash)
        else
          raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
        end
    end
  end

  def insert_run!(%Capsule{} = capsule, %Genome{} = genome, attrs \\ %{}) do
    suffix = suffix()
    assignment = assignment_for_run(capsule, attrs)
    run_source = Map.get(attrs, :run_source, run_source(capsule, genome, assignment))
    verdict_json = Map.get(attrs, :verdict_json, verdict_json())

    defaults = %{
      run_id: "run_#{suffix}",
      capsule_id: capsule.capsule_id,
      assignment_ref: assignment && assignment.assignment_ref,
      genome_id: genome.genome_id,
      canonical_run_id: nil,
      executor_type: "genome",
      harness_type: genome.harness_type,
      harness_version: genome.harness_version,
      split: capsule.split,
      status: Map.get(attrs, :status, "validation_pending"),
      raw_score: Map.get(attrs, :raw_score, 4.0),
      normalized_score: Map.get(attrs, :normalized_score, 0.8),
      score_source: "workspace",
      analysis_py: "print('analysis')\n",
      protocol_md: capsule.protocol_md,
      rubric_json: capsule.rubric_json,
      task_json: capsule.task_json,
      verdict_json: verdict_json,
      final_answer_md: "Final answer",
      report_html: "<p>report</p>",
      run_log: "log",
      artifact_source: capsule.artifact_source,
      genome_source: genome.source,
      run_source: run_source
    }

    %Run{}
    |> Run.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_validation!(%Run{} = run, attrs \\ %{}) do
    suffix = suffix()
    review_source = Map.get(attrs, :review_source, review_source(run, attrs))

    defaults = %{
      validation_id: "val_#{suffix}",
      run_id: run.run_id,
      canonical_review_id: nil,
      role: Map.get(attrs, :role, "official"),
      method: Map.get(attrs, :method, "replay"),
      result: Map.get(attrs, :result, "confirmed"),
      reproduced_raw_score: Map.get(attrs, :reproduced_raw_score, run.raw_score),
      reproduced_normalized_score:
        Map.get(attrs, :reproduced_normalized_score, run.normalized_score),
      tolerance_raw_abs: Map.get(attrs, :tolerance_raw_abs, 0.01),
      summary: Map.get(attrs, :summary, "Replay confirmed the run."),
      review_source: review_source,
      verdict_json: Map.get(attrs, :verdict_json, run.verdict_json),
      report_html: Map.get(attrs, :report_html, "<p>report</p>"),
      run_log: Map.get(attrs, :run_log, "log")
    }

    %Validation{}
    |> Validation.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def insert_validated_benchmark_bundle!(attrs \\ %{}) do
    capsule =
      insert_capsule!(
        Map.merge(
          %{split: "benchmark", assignment_policy: "select"},
          Map.take(attrs, [:capsule_id, :title, :split, :assignment_policy, :provider])
        )
      )

    assignment = insert_assignment!(capsule, %{origin: capsule.assignment_policy})
    genome = insert_genome!(Map.take(attrs, [:genome_id, :label, :model_id, :harness_type]))

    run =
      insert_run!(
        capsule,
        genome,
        Map.merge(
          %{assignment: assignment, status: "validated"},
          Map.take(attrs, [:run_id, :raw_score, :normalized_score])
        )
      )

    validation =
      insert_validation!(
        run,
        Map.merge(
          %{role: "official", method: "replay", result: "confirmed"},
          Map.take(attrs, [:validation_id])
        )
      )

    %{capsule: capsule, assignment: assignment, genome: genome, run: run, validation: validation}
  end

  def run_submit_payload(%Capsule{} = capsule, attrs \\ %{}) do
    genome = genome_source(Map.take(attrs, [:genome_id, :label, :model_id, :harness_type]))
    split = Map.get(attrs, :split, capsule.split)
    assignment_ref = Map.get(attrs, :assignment_ref)

    %{
      "run_id" => Map.get(attrs, :run_id, "run_submit_#{suffix()}"),
      "capsule_id" => capsule.capsule_id,
      "assignment_ref" => assignment_ref,
      "artifact_source" => capsule.artifact_source,
      "genome_source" => genome,
      "run_source" => %{
        "schema_version" => "techtree.bbh.run-source.v1",
        "artifact_ref" => capsule.capsule_id,
        "executor" => %{
          "type" => "genome",
          "id" => genome["genome_id"],
          "harness" => genome["harness_type"],
          "harness_version" => genome["harness_version"],
          "profile" => genome["tool_profile"]
        },
        "instance" => %{
          "instance_ref" => capsule.instance_ref || capsule.capsule_id,
          "family_ref" => capsule.family_ref,
          "seed" => nil
        },
        "origin" => %{
          "workload" => "bbh",
          "transport" => "api",
          "trigger" => "assignment"
        },
        "status" => Map.get(attrs, :status, "completed"),
        "score" => %{
          "raw" => Map.get(attrs, :raw_score, 4.0),
          "normalized" => Map.get(attrs, :normalized_score, 0.8)
        },
        "bbh" => %{
          "split" => split,
          "genome_ref" => genome["genome_id"],
          "provider" => capsule.provider,
          "assignment_ref" => assignment_ref,
          "keep_decision" => "pending"
        }
      },
      "workspace" => %{
        "task_json" => capsule.task_json,
        "protocol_md" => capsule.protocol_md,
        "rubric_json" => capsule.rubric_json,
        "analysis_py" => "print('analysis')\n",
        "verdict_json" =>
          verdict_json(Map.get(attrs, :raw_score, 4.0), Map.get(attrs, :normalized_score, 0.8)),
        "final_answer_md" => "Final answer",
        "report_html" => "<p>report</p>",
        "run_log" => "log"
      }
    }
  end

  def validation_submit_payload(%Run{} = run, attrs \\ %{}) do
    %{
      "validation_id" => Map.get(attrs, :validation_id, "val_submit_#{suffix()}"),
      "run_id" => run.run_id,
      "review_source" => review_source(run, attrs),
      "workspace" => %{
        "verdict_json" => run.verdict_json,
        "report_html" => "<p>report</p>",
        "run_log" => "log"
      }
    }
  end

  def genome_source(attrs \\ %{}) do
    suffix = suffix()
    genome_id = Map.get(attrs, :genome_id, "gen_#{suffix}")

    %{
      "schema_version" => "techtree.bbh.genome-source.v1",
      "genome_id" => genome_id,
      "label" => Map.get(attrs, :label, "Genome #{suffix}"),
      "parent_genome_ref" => nil,
      "model_id" => Map.get(attrs, :model_id, "gpt-test"),
      "harness_type" => Map.get(attrs, :harness_type, "hermes"),
      "harness_version" => "1.0.0",
      "prompt_pack_version" => "bbh-v0.1",
      "skill_pack_version" => "techtree-bbh-v0.1",
      "tool_profile" => "bbh",
      "runtime_image" => "local-runtime",
      "helper_code_hash" => nil,
      "data_profile" => "python-only",
      "axes" => %{},
      "notes" => nil
    }
  end

  def verdict_json(raw \\ 4.0, normalized \\ 0.8) do
    %{
      "decision" => "support",
      "justification" => "The notebook supports the hypothesis.",
      "metrics" => %{
        "raw_score" => raw,
        "normalized_score" => normalized
      },
      "rubric_breakdown" => [%{"id" => "final_objective", "points" => raw}],
      "status" => "ok"
    }
  end

  defp run_source(capsule, genome, assignment) do
    %{
      "schema_version" => "techtree.bbh.run-source.v1",
      "artifact_ref" => capsule.capsule_id,
      "executor" => %{
        "type" => "genome",
        "id" => genome.genome_id,
        "harness" => genome.harness_type,
        "harness_version" => genome.harness_version,
        "profile" => genome.tool_profile
      },
      "instance" => %{
        "instance_ref" => capsule.instance_ref || capsule.capsule_id,
        "family_ref" => capsule.family_ref,
        "seed" => nil
      },
      "origin" => %{
        "workload" => "bbh",
        "transport" => "api",
        "trigger" => "assignment"
      },
      "bbh" => %{
        "split" => capsule.split,
        "genome_ref" => genome.genome_id,
        "provider" => capsule.provider,
        "assignment_ref" => assignment && assignment.assignment_ref,
        "keep_decision" => "pending"
      }
    }
  end

  defp review_source(run, attrs) do
    %{
      "schema_version" => "techtree.bbh.review-source.v1",
      "target" => %{"type" => "run", "id" => run.run_id},
      "kind" => "validation",
      "method" => Map.get(attrs, :method, "replay"),
      "result" => Map.get(attrs, :result, "confirmed"),
      "summary" => Map.get(attrs, :summary, "Replay confirmed the run."),
      "bbh" => %{
        "role" => Map.get(attrs, :role, "official"),
        "reproduced_raw_score" => Map.get(attrs, :reproduced_raw_score, run.raw_score),
        "reproduced_normalized_score" =>
          Map.get(attrs, :reproduced_normalized_score, run.normalized_score),
        "raw_abs_tolerance" => Map.get(attrs, :tolerance_raw_abs, 0.01),
        "assignment_ref" => run.assignment_ref
      }
    }
  end

  defp assignment_for_run(capsule, attrs) do
    cond do
      Map.has_key?(attrs, :assignment) ->
        Map.get(attrs, :assignment)

      capsule.split in ["benchmark", "challenge"] ->
        insert_assignment!(capsule, %{origin: capsule.assignment_policy})

      true ->
        nil
    end
  end

  defp normalized_bundle_hash(source) do
    source
    |> Map.drop(["schema_version", "label", "parent_genome_ref", "notes", "genome_id"])
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp suffix do
    System.unique_integer([:positive])
    |> Integer.to_string(36)
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end

  def insert_published_challenge_bundle!(attrs \\ %{}) do
    %{capsule: capsule, publication_artifact_id: artifact_id, publication_review_id: review_id} =
      insert_published_challenge_capsule!(attrs)

    assignment = insert_assignment!(capsule, %{origin: capsule.assignment_policy})
    genome = insert_genome!(Map.take(attrs, [:genome_id, :label, :model_id, :harness_type]))

    run =
      insert_run!(
        capsule,
        genome,
        Map.merge(
          %{assignment: assignment, status: "validated"},
          Map.take(attrs, [:run_id, :raw_score, :normalized_score])
        )
      )

    validation =
      insert_validation!(
        run,
        Map.merge(
          %{role: "official", method: "replay", result: "confirmed"},
          Map.take(attrs, [:validation_id])
        )
      )

    %{
      capsule: capsule,
      assignment: assignment,
      genome: genome,
      run: run,
      validation: validation,
      publication_artifact_id: artifact_id,
      publication_review_id: review_id
    }
  end

  def insert_published_challenge_capsule!(attrs \\ %{}) do
    capsule =
      insert_capsule!(
        Map.merge(
          %{
            split: "draft",
            assignment_policy: "operator",
            provider: "techtree",
            family_ref: Map.get(attrs, :family_ref, "challenge-family"),
            instance_ref: nil,
            mode: "family"
          },
          Map.take(attrs, [:capsule_id, :title, :provider_ref, :family_ref, :instance_ref, :mode])
        )
      )

    artifact_id = Map.get(attrs, :publication_artifact_id, random_bytes32("a1"))
    review_id = Map.get(attrs, :publication_review_id, random_bytes32("b2"))

    Repo.insert!(%TechTree.V1.Node{
      id: artifact_id,
      node_type: 1,
      author: zero_address(),
      subject_id: artifact_id,
      aux_id: artifact_id,
      payload_hash: sha(),
      schema_version: 1,
      verification_status: "verified",
      header: %{"id" => artifact_id},
      manifest: %{"title" => capsule.title},
      payload_index: %{}
    })

    Repo.insert!(%TechTree.V1.Artifact{
      id: artifact_id,
      kind: "capsule",
      title: capsule.title,
      summary: capsule.hypothesis,
      has_eval: true,
      eval_mode: capsule.mode
    })

    Repo.insert!(%TechTree.V1.Node{
      id: review_id,
      node_type: 3,
      author: zero_address(),
      subject_id: review_id,
      aux_id: artifact_id,
      payload_hash: sha(),
      schema_version: 1,
      verification_status: "verified",
      header: %{"id" => review_id},
      manifest: %{
        "target" => %{"type" => "artifact", "id" => artifact_id},
        "kind" => "challenge",
        "method" => "manual",
        "result" => "confirmed",
        "summary" => "Published for the public challenge lane"
      },
      payload_index: %{}
    })

    Repo.insert!(%TechTree.V1.Review{
      id: review_id,
      target_type: "artifact",
      target_id: artifact_id,
      kind: "challenge",
      method: "manual",
      result: "confirmed",
      scope_level: "whole",
      scope_path: nil
    })

    {:ok, capsule} =
      TechTree.BBH.promote_challenge_capsule(capsule.capsule_id, %{
        "publication_artifact_id" => artifact_id,
        "publication_review_id" => review_id,
        "assignment_policy" => Map.get(attrs, :assignment_policy, "auto_or_select")
      })

    %{
      capsule: capsule,
      publication_artifact_id: artifact_id,
      publication_review_id: review_id
    }
  end

  defp random_bytes32(prefix) do
    "0x" <> prefix <> Base.encode16(:crypto.strong_rand_bytes(31), case: :lower)
  end

  defp sha do
    "sha256:" <> String.duplicate("1", 64)
  end

  defp zero_address do
    "0x0000000000000000000000000000000000000000"
  end
end
