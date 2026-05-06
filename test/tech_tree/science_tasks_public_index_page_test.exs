defmodule TechTree.ScienceTasksPublicIndexPageTest do
  use TechTree.DataCase, async: false

  alias TechTree.Agents
  alias TechTree.ScienceTasks

  test "public_index_page returns filters, counts, and grouped task cards" do
    checklist_task = create_task!("chemistry", "kinetics")
    ready_task = create_evidence_ready_task!("biology", "ecology")

    assert {:ok, page} = ScienceTasks.public_index_page(%{})

    assert page.stage_filter == nil
    assert page.domains == ["biology", "chemistry"]
    assert page.fields == ["ecology", "kinetics"]
    assert page.counts["checklist_fix"] == 1
    assert page.counts["evidence_ready"] == 1

    assert Enum.map(page.tasks_by_stage["checklist_fix"], & &1.node_id) == [
             checklist_task.node_id
           ]

    assert Enum.map(page.tasks_by_stage["evidence_ready"], & &1.node_id) == [ready_task.node_id]

    assert List.first(page.tasks_by_stage["evidence_ready"]).evidence_label ==
             "proof matches files"
  end

  test "public_index_page applies the current filters" do
    create_task!("chemistry", "kinetics")
    ready_task = create_evidence_ready_task!("biology", "ecology")

    assert {:ok, page} =
             ScienceTasks.public_index_page(%{
               "stage" => "evidence_ready",
               "science_domain" => "biology"
             })

    assert page.stage_filter == "evidence_ready"
    assert page.domain_filter == "biology"
    assert page.visible_stages == ["evidence_ready"]
    assert Enum.map(page.tasks, & &1.node_id) == [ready_task.node_id]
  end

  test "public_index_page returns the clean science tasks href for an invalid stage" do
    assert {:error, :science_task_invalid_stage, %{redirect_href: redirect_href}} =
             ScienceTasks.public_index_page(%{
               "stage" => "not-a-stage",
               "science_domain" => "biology",
               "science_field" => "ecology"
             })

    assert redirect_href == "/science-tasks?science_field=ecology&science_domain=biology"
  end

  test "public_index_href includes only active filters" do
    assert ScienceTasks.public_index_href(nil, nil, nil) == "/science-tasks"

    assert ScienceTasks.public_index_href("evidence_ready", "biology", nil) ==
             "/science-tasks?science_domain=biology&stage=evidence_ready"
  end

  defp create_evidence_ready_task!(science_domain, science_field) do
    agent = create_agent!(science_domain)
    {:ok, task} = ScienceTasks.create_task(agent, base_input(science_domain, science_field))

    {:ok, _task} =
      base_input(science_domain, science_field)
      |> Map.put("checklist", checklist_map("pass"))
      |> then(&ScienceTasks.update_checklist(agent, task.node_id, &1))

    {:ok, ready_task} =
      base_input(science_domain, science_field)
      |> Map.put("oracle_run", %{
        "command" => "harbor run -a oracle",
        "summary" => "Oracle passed"
      })
      |> Map.put("frontier_run", %{
        "command" => "harbor run -a codex",
        "summary" => "Frontier missed one step"
      })
      |> then(&ScienceTasks.update_evidence(agent, task.node_id, &1))

    ready_task
  end

  defp create_task!(science_domain, science_field) do
    agent = create_agent!(science_domain)
    {:ok, task} = ScienceTasks.create_task(agent, base_input(science_domain, science_field))
    task
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

  defp base_input(science_domain, science_field) do
    unique = System.unique_integer([:positive])
    task_slug = "#{science_domain}-#{science_field}-#{unique}"

    %{
      "title" => "#{science_domain} #{science_field} task #{unique}",
      "summary" => "Science task for public page coverage.",
      "science_domain" => science_domain,
      "science_field" => science_field,
      "task_slug" => task_slug,
      "structured_output_shape" => %{"answer" => "string"},
      "claimed_expert_time" => "3 hours",
      "threshold_rationale" => "Thresholds are calibrated.",
      "anti_cheat_notes" => "Answers stay hidden.",
      "reproducibility_notes" => "The environment is pinned.",
      "dependency_pinning_status" => "Pinned with exact versions.",
      "canary_status" => "Canary strings are present.",
      "failure_analysis" => "The task remains valid when the frontier model misses it.",
      "packet_files" => %{
        "instruction.md" => %{"encoding" => "utf8", "content" => "# Instruction\n"},
        "task.toml" => %{"encoding" => "utf8", "content" => "name = \"#{task_slug}\"\n"},
        "tests/test_task.py" => %{
          "encoding" => "utf8",
          "content" => "def test_task():\n    assert True\n"
        },
        "solution-notes.md" => %{"encoding" => "utf8", "content" => "# Solution notes\n"},
        "scripts/README.md" => %{"encoding" => "utf8", "content" => "# Scripts\n"},
        "task-notes.md" => %{"encoding" => "utf8", "content" => "# Task notes\n"}
      }
    }
  end

  defp checklist_map(status) do
    ScienceTasks.checklist_keys()
    |> Enum.reduce(%{}, fn key, acc ->
      Map.put(acc, key, %{"status" => status, "note" => "Checked in public page fixture."})
    end)
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end
end
