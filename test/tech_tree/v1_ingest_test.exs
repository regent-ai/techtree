defmodule TechTree.V1IngestTest do
  use TechTree.DataCase, async: false

  alias TechTree.Repo
  alias TechTree.V1
  alias TechTree.V1.{Node, RejectedIngest}
  import TechTree.V1ChainSupport

  setup do
    previous_ethereum = Application.get_env(:tech_tree, :ethereum)
    previous_lighthouse = Application.get_env(:tech_tree, TechTree.IPFS.LighthouseClient)

    on_exit(fn ->
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

  test "ingest_published_event persists a verified artifact from chain data" do
    fixture = load_fixture!("artifact_plain")
    registry_address = "0x4444444444444444444444444444444444444444"
    manifest_cid = "bafy-manifest-artifact-plain"
    payload_cid = "bafy-payload-artifact-plain"
    tx_hash = "0x" <> String.duplicate("d", 64)

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

    assert {:ok, node} = V1.ingest_published_event(%{"tx_hash" => tx_hash})
    assert node.id == fixture.header["id"]
    assert node.manifest_cid == manifest_cid
    assert node.payload_cid == payload_cid
    assert node.tx_hash == tx_hash
    assert node.verification_status == "verified"

    persisted = Repo.get!(Node, fixture.header["id"])
    assert persisted.manifest["title"] == fixture.manifest["title"]
    assert persisted.payload_index["schema_version"] == "techtree.payload-index.v1"
  end

  test "ingest_published_event records a rejected ingest when chain header fails verification" do
    fixture = load_fixture!("artifact_plain")
    bad_header = Map.put(fixture.header, "subject_id", "0x" <> String.duplicate("1", 64))
    registry_address = "0x4444444444444444444444444444444444444444"
    manifest_cid = "bafy-manifest-artifact-plain-bad"
    payload_cid = "bafy-payload-artifact-plain-bad"

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
          header: bad_header,
          receipt:
            build_receipt(bad_header,
              registry_address: registry_address,
              manifest_cid: manifest_cid,
              payload_cid: payload_cid
            )
        )
    )

    assert {:error, {:verification_failed, _rejected_id}} =
             V1.ingest_published_event(%{"tx_hash" => "0x" <> String.duplicate("e", 64)})

    rejected = Repo.one!(RejectedIngest)
    assert rejected.node_id == fixture.header["id"]
    assert rejected.reason == "verification_failed"
    assert rejected.manifest_cid == manifest_cid
    assert rejected.payload_cid == payload_cid
  end
end
