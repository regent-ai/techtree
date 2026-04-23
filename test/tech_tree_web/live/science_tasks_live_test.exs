defmodule TechTreeWeb.ScienceTasksLiveTest do
  use TechTreeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TechTree.ScienceTasks
  alias TechTree.Agents

  test "science task board renders grouped tasks", %{conn: conn} do
    task = create_evidence_ready_task!("science-board")

    {:ok, view, _html} = live(conn, ~p"/science-tasks")

    assert has_element?(view, "#science-tasks-page")
    assert render(view) =~ task.node.title
    assert render(view) =~ "Evidence ready"
  end

  test "science task detail renders checklist and packet files", %{conn: conn} do
    task = create_evidence_ready_task!("science-detail")

    {:ok, view, _html} = live(conn, ~p"/science-tasks/#{task.node_id}")

    assert has_element?(view, "#science-task-detail-page")
    assert render(view) =~ task.node.title
    assert render(view) =~ "Task packet"
    assert render(view) =~ "instruction and tests match exactly"
    assert render(view) =~ "instruction.md"
  end

  defp create_evidence_ready_task!(label_prefix) do
    agent = create_agent!(label_prefix)
    {:ok, task} = ScienceTasks.create_task(agent, base_input("#{label_prefix} task"))

    {:ok, _task} =
      base_input("#{label_prefix} task")
      |> Map.put("checklist", checklist_map("pass"))
      |> then(&ScienceTasks.update_checklist(agent, task.node_id, &1))

    {:ok, ready_task} =
      base_input("#{label_prefix} task")
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

  defp create_agent!(label_prefix) do
    unique = System.unique_integer([:positive])

    Agents.upsert_verified_agent!(%{
      "chain_id" => "84532",
      "registry_address" => random_eth_address(),
      "token_id" => Integer.to_string(unique),
      "wallet_address" => random_eth_address(),
      "label" => "#{label_prefix}-#{unique}"
    })
  end

  defp base_input(title) do
    %{
      "title" => title,
      "summary" => "Science task for live view coverage.",
      "science_domain" => "life-sciences",
      "science_field" => "biology",
      "task_slug" => "science-view",
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
        "task.toml" => %{"encoding" => "utf8", "content" => "name = \"science-view\"\n"},
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
      Map.put(acc, key, %{"status" => status, "note" => "Checked in live fixture."})
    end)
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end
end
