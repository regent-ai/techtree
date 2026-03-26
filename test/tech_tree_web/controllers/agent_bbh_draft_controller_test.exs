defmodule TechTreeWeb.AgentBbhDraftControllerTest do
  use TechTreeWeb.ConnCase, async: true

  import TechTreeWeb.TestSupport.SiwaIntegrationSupport

  alias TechTree.BBHFixtures

  test "draft routes create, list, propose, apply, and ready a BBH draft", %{conn: conn} do
    wallet = "0x1111111111111111111111111111111111111111"

    create_response =
      conn
      |> with_siwa_headers(wallet: wallet)
      |> post("/v1/agent/bbh/drafts", %{
        "title" => "Draft Capsule",
        "seed" => "BBH",
        "workspace" => %{
          "notebook_py" => "print('draft')\n",
          "hypothesis_md" => "Hypothesis",
          "protocol_md" => "Protocol",
          "rubric_json" => %{"criteria" => []},
          "capsule_source" => %{"schema_version" => "techtree.bbh.capsule-source.v1"},
          "recommended_genome_source" => %{"schema_version" => "techtree.bbh.genome-source.v1"},
          "genome_notes_md" => "Notes"
        }
      })
      |> json_response(200)

    capsule_id = get_in(create_response, ["data", "capsule", "capsule_id"])
    assert get_in(create_response, ["data", "capsule", "workflow_state"]) == "authoring"
    assert get_in(create_response, ["data", "workspace", "notebook_py"]) =~ "print"

    list_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(wallet: wallet)
      |> get("/v1/agent/bbh/drafts")
      |> json_response(200)

    assert Enum.any?(list_response["data"], &(&1["capsule_id"] == capsule_id))

    proposal_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(wallet: "0x2222222222222222222222222222222222222222")
      |> post("/v1/agent/bbh/drafts/#{capsule_id}/proposals", %{
        "summary" => "Tightened rubric",
        "workspace_manifest_hash" => "sha256:#{String.duplicate("1", 64)}",
        "workspace" => %{
          "notebook_py" => "print('proposal')\n",
          "hypothesis_md" => "Hypothesis",
          "protocol_md" => "Protocol 2",
          "rubric_json" => %{"criteria" => ["clarity"]},
          "capsule_source" => %{"schema_version" => "techtree.bbh.capsule-source.v1"}
        }
      })
      |> json_response(200)

    proposal_id = get_in(proposal_response, ["data", "proposal", "proposal_id"])

    apply_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(wallet: wallet)
      |> post("/v1/agent/bbh/drafts/#{capsule_id}/proposals/#{proposal_id}/apply", %{})
      |> json_response(200)

    assert get_in(apply_response, ["data", "workspace", "protocol_md"]) == "Protocol 2"

    ready_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(wallet: wallet)
      |> post("/v1/agent/bbh/drafts/#{capsule_id}/ready", %{})
      |> json_response(200)

    assert get_in(ready_response, ["data", "capsule", "workflow_state"]) == "review_ready"
  end

  test "only the owner can mark a draft ready", %{conn: conn} do
    capsule =
      BBHFixtures.insert_capsule!(%{
        split: "draft",
        provider: "techtree",
        assignment_policy: "operator",
        owner_wallet_address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      })

    assert %{"error" => %{"code" => "bbh_draft_not_owned"}} =
             conn
             |> with_siwa_headers(wallet: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
             |> post("/v1/agent/bbh/drafts/#{capsule.capsule_id}/ready", %{})
             |> json_response(403)
  end
end
