defmodule TechTreeWeb.RuntimePublishControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import TechTree.V1ChainSupport

  setup do
    previous_secret = Application.get_env(:tech_tree, :internal_shared_secret, "")
    previous_ethereum = Application.get_env(:tech_tree, :ethereum)
    previous_lighthouse = Application.get_env(:tech_tree, TechTree.IPFS.LighthouseClient)

    Application.put_env(:tech_tree, :internal_shared_secret, "test-internal-secret")

    on_exit(fn ->
      Application.put_env(:tech_tree, :internal_shared_secret, previous_secret)

      if is_nil(previous_ethereum) do
        Application.delete_env(:tech_tree, :ethereum)
      else
        Application.put_env(:tech_tree, :ethereum, previous_ethereum)
      end

      if is_nil(previous_lighthouse) do
        Application.delete_env(:tech_tree, TechTree.IPFS.LighthouseClient)
      else
        Application.put_env(:tech_tree, TechTree.IPFS.LighthouseClient, previous_lighthouse)
      end
    end)

    :ok
  end

  test "internal published-node ingest requires the shared secret", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/api/internal/v1/published-nodes/ingest", %{
        "tx_hash" => "0x" <> String.duplicate("f", 64)
      })

    assert %{"error" => %{"code" => "internal_auth_required"}} = json_response(conn, 401)
  end

  test "agent runtime write paths require SIWA auth before request handling", %{conn: conn} do
    paths = [
      "/v1/agent/runtime/publish/submit",
      "/v1/agent/runtime/runs/run-1/validate",
      "/v1/agent/runtime/artifacts/artifact-1/challenge",
      "/v1/agent/runtime/runs/run-1/challenge"
    ]

    Enum.each(paths, fn path ->
      response =
        conn
        |> recycle()
        |> put_req_header("accept", "application/json")
        |> post(path, %{})

      assert %{"error" => %{"code" => "agent_auth_required"}} = json_response(response, 401)
    end)
  end

  test "internal published-node ingest persists a verified node", %{conn: conn} do
    fixture = load_fixture!("artifact_plain")
    registry_address = "0x4444444444444444444444444444444444444444"
    manifest_cid = "bafy-manifest-controller"
    payload_cid = "bafy-payload-controller"
    tx_hash = "0x" <> String.duplicate("a", 64)

    {gateway_spec, gateway_base} =
      gateway_child_spec(%{
        manifest_cid => fixture.manifest,
        payload_cid => fixture.payload_index
      })

    _gateway = start_supervised!(gateway_spec)

    Application.put_env(:tech_tree, TechTree.IPFS.LighthouseClient,
      gateway_base: gateway_base,
      mock_uploads: true
    )

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: registry_address,
      rpc_client:
        rpc_client_for_submission(
          registry_address: registry_address,
          header: fixture.header,
          receipt:
            build_receipt(fixture.header,
              registry_address: registry_address,
              manifest_cid: manifest_cid,
              payload_cid: payload_cid
            )
        )
    )

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-tech-tree-secret", "test-internal-secret")
      |> post("/api/internal/v1/published-nodes/ingest", %{"tx_hash" => tx_hash})

    assert %{
             "data" => %{
               "id" => id,
               "manifest_cid" => ^manifest_cid,
               "payload_cid" => ^payload_cid,
               "tx_hash" => ^tx_hash,
               "verification_status" => "verified"
             }
           } = json_response(conn, 201)

    assert id == fixture.header["id"]
  end
end
