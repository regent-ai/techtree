defmodule TechTreeWeb.ScienceTaskControllerTest do
  use TechTreeWeb.ConnCase, async: false

  alias TechTree.Agents
  alias TechTree.ScienceTasks

  test "public list and detail expose stored science tasks", %{conn: conn} do
    agent = create_agent!("science-public")
    {:ok, task} = ScienceTasks.create_task(agent, base_input("Visible science task"))

    assert %{"data" => [first | _rest]} =
             conn
             |> get("/v1/science-tasks")
             |> json_response(200)

    assert first["node_id"] == task.node_id
    assert first["workflow_state"] == "checklist_fix"

    assert %{"data" => detail} =
             Phoenix.ConnTest.build_conn()
             |> get("/v1/science-tasks/#{task.node_id}")
             |> json_response(200)

    assert detail["title"] == "Visible science task"
    assert detail["packet_files"]["instruction.md"]["encoding"] == "utf8"
  end

  test "agent flow moves through checklist, evidence, submit, and review states", %{conn: conn} do
    headers = create_agent_headers!("science-agent")

    create_response =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/agent/science-tasks", base_input("Task flow"))
      |> json_response(201)

    assert %{
             "data" => %{
               "node_id" => node_id,
               "workflow_state" => "checklist_fix"
             }
           } = create_response

    checklist_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> post("/v1/agent/science-tasks/#{node_id}/checklist", checklist_input("Task flow"))
      |> json_response(200)

    assert checklist_response["data"]["workflow_state"] == "checklist_fix"

    evidence_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> post("/v1/agent/science-tasks/#{node_id}/evidence", evidence_input("Task flow"))
      |> json_response(200)

    assert evidence_response["data"]["workflow_state"] == "evidence_ready"

    submit_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> post("/v1/agent/science-tasks/#{node_id}/submit", submit_input("Task flow"))
      |> json_response(200)

    assert submit_response["data"]["workflow_state"] == "submitted"

    review_fix_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> post(
        "/v1/agent/science-tasks/#{node_id}/review-update",
        review_input("Task flow", 2, true, false)
      )
      |> json_response(200)

    assert review_fix_response["data"]["workflow_state"] == "review_fix"

    merge_ready_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(headers)
      |> post(
        "/v1/agent/science-tasks/#{node_id}/review-update",
        review_input("Task flow", 0, false, true)
      )
      |> json_response(200)

    assert merge_ready_response["data"]["workflow_state"] == "merge_ready"
  end

  test "duplicate create returns a clean validation error instead of crashing", %{conn: conn} do
    headers = create_agent_headers!("science-duplicate")

    assert %{"data" => %{"node_id" => _node_id}} =
             conn
             |> with_siwa_headers(headers)
             |> post("/v1/agent/science-tasks", base_input("Duplicate task"))
             |> json_response(201)

    assert %{
             "error" => %{
               "code" => "science_task_invalid",
               "details" => %{"publish_idempotency_key" => [_ | _]}
             }
           } =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(headers)
             |> post("/v1/agent/science-tasks", base_input("Duplicate task"))
             |> json_response(422)
  end

  test "bad science task ids return normal errors", %{conn: conn} do
    headers = create_agent_headers!("science-invalid-id")

    assert %{"error" => %{"code" => "invalid_science_task_id"}} =
             conn
             |> get("/v1/science-tasks/not-an-int")
             |> json_response(422)

    assert %{
             "error" => %{
               "code" => "science_task_checklist_failed",
               "message" => "science_task_invalid_id"
             }
           } =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(headers)
             |> post(
               "/v1/agent/science-tasks/not-an-int/checklist",
               checklist_input("Invalid id")
             )
             |> json_response(422)
  end

  test "create rejects malformed structured output shape", %{conn: conn} do
    headers = create_agent_headers!("science-shape")

    assert %{
             "error" => %{
               "code" => "science_task_create_failed",
               "message" => "science_task_structured_output_shape_invalid"
             }
           } =
             conn
             |> with_siwa_headers(headers)
             |> post(
               "/v1/agent/science-tasks",
               Map.put(base_input("Bad structured output"), "structured_output_shape", "answer")
             )
             |> json_response(422)
  end

  test "evidence rejects mixed key_lines and review update rejects bad timestamps", %{conn: conn} do
    headers = create_agent_headers!("science-review-validation")

    %{"data" => %{"node_id" => node_id}} =
      conn
      |> with_siwa_headers(headers)
      |> post("/v1/agent/science-tasks", base_input("Validation task"))
      |> json_response(201)

    assert %{
             "error" => %{
               "code" => "science_task_evidence_failed",
               "message" => "science_task_key_lines_invalid"
             }
           } =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(headers)
             |> post(
               "/v1/agent/science-tasks/#{node_id}/evidence",
               evidence_input("Validation task")
               |> put_in(["oracle_run", "key_lines"], ["first line", 7])
             )
             |> json_response(422)

    assert %{
             "error" => %{
               "code" => "science_task_review_failed",
               "message" => "science_task_latest_fix_at_invalid"
             }
           } =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(headers)
             |> post(
               "/v1/agent/science-tasks/#{node_id}/review-update",
               review_input("Validation task", 1, true, false)
               |> Map.put("latest_fix_at", "not-a-datetime")
             )
             |> json_response(422)
  end

  defp create_agent_headers!(label_prefix) do
    unique = System.unique_integer([:positive])

    wallet = random_eth_address()
    registry = random_eth_address()
    token_id = Integer.to_string(unique)

    agent =
      Agents.upsert_verified_agent!(%{
        "chain_id" => "84532",
        "registry_address" => registry,
        "token_id" => token_id,
        "wallet_address" => wallet,
        "label" => "#{label_prefix}-#{unique}"
      })

    %{agent: agent, wallet: wallet, chain_id: "84532", registry: registry, token_id: token_id}
  end

  defp with_siwa_headers(conn, headers) do
    TechTreeWeb.TestSupport.SiwaIntegrationSupport.with_siwa_headers(conn,
      wallet: headers.wallet,
      chain_id: headers.chain_id,
      registry_address: headers.registry,
      token_id: headers.token_id
    )
  end

  defp create_agent!(label_prefix) do
    create_agent_headers!(label_prefix).agent
  end

  defp base_input(title) do
    %{
      "title" => title,
      "summary" => "Review-ready science task packet.",
      "science_domain" => "life-sciences",
      "science_field" => "biology",
      "task_slug" => "science-flow",
      "structured_output_shape" => %{"answer" => "string"},
      "claimed_expert_time" => "3 hours",
      "threshold_rationale" => "Thresholds are calibrated against the reference solution.",
      "anti_cheat_notes" => "Hidden answers stay outside the visible packet and tests.",
      "reproducibility_notes" => "The environment is pinned for reruns.",
      "dependency_pinning_status" => "Pinned with exact versions in task files.",
      "canary_status" => "Canary strings are present in the packet.",
      "failure_analysis" =>
        "The task stays valid because the workflow is real even when a frontier model misses it.",
      "packet_files" => packet_files()
    }
  end

  defp checklist_input(title) do
    Map.put(base_input(title), "checklist", checklist_map("pass"))
  end

  defp evidence_input(title) do
    base_input(title)
    |> Map.put("oracle_run", %{"command" => "harbor run -a oracle", "summary" => "Oracle passed"})
    |> Map.put("frontier_run", %{
      "command" => "harbor run -a codex",
      "summary" => "Frontier failed on hidden validation"
    })
  end

  defp submit_input(title) do
    base_input(title)
    |> Map.put(
      "harbor_pr_url",
      "https://github.com/harbor-framework/terminal-bench-science/pull/123"
    )
    |> Map.put("latest_review_follow_up_note", "Ready for the first Harbor pass.")
  end

  defp review_input(title, open_concerns, unanswered, rerun_after_fix) do
    submit_input(title)
    |> Map.put("open_reviewer_concerns_count", open_concerns)
    |> Map.put("any_concern_unanswered", unanswered)
    |> Map.put("latest_rerun_after_latest_fix", rerun_after_fix)
    |> Map.put("latest_fix_at", "2026-04-20T13:00:00Z")
    |> Map.put("last_rerun_at", "2026-04-21T15:30:00Z")
  end

  defp checklist_map(status) do
    ScienceTasks.checklist_keys()
    |> Enum.reduce(%{}, fn key, acc ->
      Map.put(acc, key, %{"status" => status, "note" => "Checked in test fixture."})
    end)
  end

  defp packet_files do
    %{
      "instruction.md" => %{
        "encoding" => "utf8",
        "content" => "# Instruction\n\nDeliver the task output."
      },
      "task.toml" => %{"encoding" => "utf8", "content" => "name = \"science-flow\"\n"},
      "tests/test_task.py" => %{
        "encoding" => "utf8",
        "content" => "def test_task():\n    assert True\n"
      },
      "solution-notes.md" => %{"encoding" => "utf8", "content" => "# Solution notes\n"},
      "scripts/README.md" => %{"encoding" => "utf8", "content" => "# Scripts\n"},
      "task-notes.md" => %{"encoding" => "utf8", "content" => "# Task notes\n"}
    }
  end

  defp random_eth_address do
    "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  end
end
