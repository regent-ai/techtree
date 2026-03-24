defmodule TechTree.V1ChainTest do
  use ExUnit.Case, async: false

  alias TechTree.V1.Chain
  import TechTree.V1ChainSupport

  setup do
    previous = Application.get_env(:tech_tree, :ethereum)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:tech_tree, :ethereum)
      else
        Application.put_env(:tech_tree, :ethereum, previous)
      end
    end)

    :ok
  end

  test "fetch_published_submission parses a valid NodePublished receipt and onchain header" do
    fixture = load_fixture!("artifact_plain")
    registry_address = "0x4444444444444444444444444444444444444444"
    manifest_cid = "bafy-manifest-artifact-plain"
    payload_cid = "bafy-payload-artifact-plain"
    tx_hash = "0x" <> String.duplicate("a", 64)

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

    assert {:ok, submission} = Chain.fetch_published_submission(%{"tx_hash" => tx_hash})
    assert submission.node_type == "artifact"
    assert submission.header == fixture.header
    assert submission.manifest_cid == manifest_cid
    assert submission.payload_cid == payload_cid
    assert submission.tx_hash == tx_hash
    assert submission.block_number == 42
    assert submission.contract_address == registry_address
    assert submission.log_index == 3
    assert %DateTime{} = submission.block_time
  end

  test "fetch_published_submission rejects wrong registry logs" do
    fixture = load_fixture!("artifact_plain")

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: "0x4444444444444444444444444444444444444444",
      rpc_client:
        rpc_client_for_submission(
          registry_address: "0x4444444444444444444444444444444444444444",
          header: fixture.header,
          receipt:
            build_receipt(fixture.header,
              registry_address: "0x5555555555555555555555555555555555555555",
              manifest_cid: "bafy-manifest",
              payload_cid: "bafy-payload"
            )
        )
    )

    assert {:error, :node_published_log_not_found} =
             Chain.fetch_published_submission(%{"tx_hash" => "0x" <> String.duplicate("b", 64)})
  end

  test "fetch_published_submission rejects mismatched expected header" do
    fixture = load_fixture!("artifact_plain")
    registry_address = "0x4444444444444444444444444444444444444444"

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
              manifest_cid: "bafy-manifest",
              payload_cid: "bafy-payload"
            )
        )
    )

    bad_header = Map.put(fixture.header, "author", "0x9999999999999999999999999999999999999999")

    assert {:error, {:header_mismatch, "author", _, _}} =
             Chain.fetch_published_submission(%{
               "tx_hash" => "0x" <> String.duplicate("c", 64),
               "header" => bad_header
             })
  end
end
