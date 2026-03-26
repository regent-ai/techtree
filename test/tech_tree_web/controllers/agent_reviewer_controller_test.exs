defmodule TechTreeWeb.AgentReviewerControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import TechTree.PhaseDApiSupport, except: [create_agent!: 1, with_siwa_headers: 2]
  import TechTreeWeb.TestSupport.SiwaIntegrationSupport

  alias TechTree.BBHFixtures

  setup do
    privy = setup_privy_config!()

    on_exit(fn ->
      privy.restore.()
    end)

    {:ok, privy: privy}
  end

  test "ORCID link start, browser callback, status, apply, and admin approval work", %{
    conn: conn,
    privy: privy
  } do
    wallet = "0x3333333333333333333333333333333333333333"

    start_response =
      conn
      |> with_siwa_headers(wallet: wallet)
      |> post("/v1/agent/reviewer/orcid/link/start", %{})
      |> json_response(200)

    request_id = get_in(start_response, ["data", "request_id"])
    start_url = get_in(start_response, ["data", "start_url"])
    assert get_in(start_response, ["data", "state"]) == "pending"

    uri = URI.parse(start_url)

    callback_response =
      Phoenix.ConnTest.build_conn()
      |> get(uri.path <> "?" <> (uri.query || ""))

    assert html_response(callback_response, 302)

    callback_uri = URI.parse(get_resp_header(callback_response, "location") |> List.first())

    completed_response =
      Phoenix.ConnTest.build_conn()
      |> get(callback_uri.path <> "?" <> (callback_uri.query || ""))
      |> html_response(200)

    assert completed_response =~ "ORCID linked"

    status_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(wallet: wallet)
      |> get("/v1/agent/reviewer/orcid/link/status/#{request_id}")
      |> json_response(200)

    assert get_in(status_response, ["data", "state"]) == "authenticated"

    assert get_in(status_response, ["data", "reviewer", "orcid_auth_kind"]) ==
             "oauth_authenticated"

    apply_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(wallet: wallet)
      |> post("/v1/agent/reviewer/apply", %{
        "domain_tags" => ["scrna-seq"],
        "experience_summary" => "Reviewed RNA capsules"
      })
      |> json_response(200)

    assert get_in(apply_response, ["data", "domain_tags"]) == ["scrna-seq"]

    admin = create_human!("review-admin", role: "admin")

    approve_response =
      Phoenix.ConnTest.build_conn()
      |> with_privy_bearer(admin.privy_user_id, privy.app_id, privy.private_pem)
      |> post("/v1/admin/reviewers/#{wallet}/approve", %{})
      |> json_response(200)

    assert get_in(approve_response, ["data", "vetting_status"]) == "approved"
  end

  test "reviewer apply rejects missing ORCID link", %{conn: conn} do
    wallet = "0x4444444444444444444444444444444444444444"

    assert %{"error" => %{"code" => "bbh_reviewer_orcid_required"}} =
             conn
             |> with_siwa_headers(wallet: wallet)
             |> post("/v1/agent/reviewer/apply", %{"domain_tags" => ["bulk-rna"]})
             |> json_response(422)
  end

  test "review routes enforce approved reviewer gating and support claim/pull/submit", %{
    conn: conn
  } do
    reviewer =
      BBHFixtures.insert_reviewer_profile!(%{
        wallet_address: "0x5555555555555555555555555555555555555555",
        vetting_status: "approved"
      })

    capsule =
      BBHFixtures.insert_capsule!(%{
        split: "draft",
        provider: "techtree",
        assignment_policy: "operator",
        owner_wallet_address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        workflow_state: "review_ready"
      })

    BBHFixtures.insert_draft_proposal!(capsule)
    request = BBHFixtures.insert_review_request!(capsule)

    list_response =
      conn
      |> with_siwa_headers(wallet: reviewer.wallet_address)
      |> get("/v1/agent/reviews/open", %{"kind" => "certification"})
      |> json_response(200)

    assert Enum.any?(list_response["data"], &(&1["request_id"] == request.request_id))

    claim_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(wallet: reviewer.wallet_address)
      |> post("/v1/agent/reviews/#{request.request_id}/claim", %{})
      |> json_response(200)

    assert get_in(claim_response, ["data", "state"]) == "claimed"

    packet_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(wallet: reviewer.wallet_address)
      |> get("/v1/agent/reviews/#{request.request_id}/packet")
      |> json_response(200)

    assert get_in(packet_response, ["data", "workspace", "notebook_py"]) =~ "print"
    assert get_in(packet_response, ["data", "prior_proposals"]) != []

    submit_response =
      Phoenix.ConnTest.build_conn()
      |> with_siwa_headers(wallet: reviewer.wallet_address)
      |> post("/v1/agent/reviews/#{request.request_id}/submit", %{
        "request_id" => request.request_id,
        "capsule_id" => capsule.capsule_id,
        "checklist_json" => %{"decision" => "approve"},
        "suggested_edits_json" => %{"edits" => []},
        "decision" => "approve",
        "summary_md" => "Approved."
      })
      |> json_response(200)

    assert get_in(submit_response, ["data", "submission", "decision"]) == "approve"

    assert %{"error" => %{"code" => "bbh_review_request_mismatch"}} =
             Phoenix.ConnTest.build_conn()
             |> with_siwa_headers(wallet: reviewer.wallet_address)
             |> post("/v1/agent/reviews/#{request.request_id}/submit", %{
               "request_id" => "wrong",
               "capsule_id" => capsule.capsule_id,
               "checklist_json" => %{"decision" => "approve"},
               "suggested_edits_json" => %{"edits" => []},
               "decision" => "approve",
               "summary_md" => "Approved."
             })
             |> json_response(422)
  end
end
