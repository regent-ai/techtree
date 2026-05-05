defmodule TechTree.EthereumTest do
  use ExUnit.Case, async: false

  alias TechTree.Ethereum
  alias TechTree.V1ChainSupport

  @valid_publish_node_params %{
    node_id: 101,
    subject_id: 0,
    aux_id: 0,
    author: "0x1111111111111111111111111111111111111111",
    payload_hash: String.duplicate("ab", 32),
    node_type: 2,
    schema_version: 1,
    flags: 0,
    manifest_cid: "bafy-manifest-101",
    payload_cid: "bafy-payload-101"
  }

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

  test "publish_node uses stub mode when rpc settings are absent" do
    Application.put_env(:tech_tree, :ethereum, mode: :auto, rpc_url: nil, registry_address: nil)

    assert {:ok, tx_hash} = Ethereum.publish_node(@valid_publish_node_params)
    assert tx_hash =~ ~r/^0x[0-9a-f]{64}$/
  end

  test "publish_node submits the canonical publishNode call in rpc mode" do
    parent = self()
    expected_tx_hash = "0x" <> String.duplicate("a", 64)

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: "0x2222222222222222222222222222222222222222",
      writer_private_key: "0x" <> String.duplicate("1", 64),
      cast_runner: fn cmd, args ->
        send(parent, {:cast_invocation, cmd, args})
        {expected_tx_hash <> "\n", 0}
      end
    )

    assert {:ok, ^expected_tx_hash} =
             Ethereum.publish_node(%{
               @valid_publish_node_params
               | payload_hash: "sha256:" <> String.duplicate("CD", 32)
             })

    assert_receive {:cast_invocation, "cast", args}

    assert Enum.member?(
             args,
             "publishNode((bytes32,bytes32,bytes32,bytes32,uint8,uint16,uint32,address),bytes,bytes)"
           )

    assert Enum.member?(
             args,
             "(0x0000000000000000000000000000000000000000000000000000000000000065,0x0000000000000000000000000000000000000000000000000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000,0xcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd,2,1,0,0x1111111111111111111111111111111111111111)"
           )

    assert Enum.member?(args, "0x626166792d6d616e69666573742d313031")
    assert Enum.member?(args, "0x626166792d7061796c6f61642d313031")
  end

  test "publish_node in explicit rpc mode surfaces missing writer key config" do
    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: "0x2222222222222222222222222222222222222222",
      writer_private_key: nil
    )

    assert {:error, {:rpc_config_missing, :writer_private_key}} =
             Ethereum.publish_node(@valid_publish_node_params)
  end

  test "fetch_receipt returns :not_found for pending rpc transaction" do
    parent = self()

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: "0x3333333333333333333333333333333333333333",
      rpc_client: fn _rpc_url, payload ->
        send(parent, {:rpc_method, payload["method"]})
        {:ok, %{"jsonrpc" => "2.0", "id" => payload["id"], "result" => nil}}
      end
    )

    assert :not_found = Ethereum.fetch_receipt("0x" <> String.duplicate("9", 64), nil)
    assert_receive {:rpc_method, "eth_getTransactionReceipt"}
  end

  test "fetch_receipt parses NodePublished receipt and verifies the stored header" do
    registry = "0x4444444444444444444444444444444444444444"
    tx_hash = "0x" <> String.duplicate("8", 64)
    header = published_header()
    manifest_cid = "bafy-manifest-artifact"
    payload_cid = "bafy-payload-artifact"

    receipt =
      V1ChainSupport.build_receipt(header,
        registry_address: registry,
        manifest_cid: manifest_cid,
        payload_cid: payload_cid
      )

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: registry,
      chain_id: 8_453,
      rpc_client:
        V1ChainSupport.rpc_client_for_submission(
          registry_address: registry,
          receipt: receipt,
          header: header,
          chain_id_hex: "0x2105"
        )
    )

    assert {:ok, receipt} =
             Ethereum.fetch_receipt(tx_hash, %{
               "node_id" => header["id"],
               "manifest_cid" => manifest_cid,
               "payload_cid" => payload_cid,
               "author" => header["author"],
               "header" => header
             })

    assert receipt.block_number == 42
    assert receipt.chain_id == 8_453
    assert receipt.contract_address == registry
    assert receipt.log_index == 3
  end

  test "fetch_receipt rejects mismatched NodePublished details" do
    registry = "0x4444444444444444444444444444444444444444"
    tx_hash = "0x" <> String.duplicate("7", 64)
    header = published_header()

    receipt =
      V1ChainSupport.build_receipt(header,
        registry_address: registry,
        manifest_cid: "bafy-manifest",
        payload_cid: "bafy-payload"
      )

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: registry,
      chain_id: 8_453,
      rpc_client:
        V1ChainSupport.rpc_client_for_submission(
          registry_address: registry,
          receipt: receipt,
          header: header,
          chain_id_hex: "0x2105"
        )
    )

    assert {:error, {:mismatch, "manifest_cid", "bafy-other", "bafy-manifest"}} =
             Ethereum.fetch_receipt(tx_hash, %{
               "node_id" => header["id"],
               "manifest_cid" => "bafy-other",
               "payload_cid" => "bafy-payload",
               "author" => header["author"],
               "header" => header
             })
  end

  defp published_header do
    %{
      "id" => "0x" <> String.pad_leading("65", 64, "0"),
      "subject_id" => "0x" <> String.duplicate("0", 64),
      "aux_id" => "0x" <> String.duplicate("0", 64),
      "payload_hash" => "sha256:" <> String.duplicate("ab", 32),
      "node_type" => 1,
      "schema_version" => 1,
      "flags" => 0,
      "author" => "0x1111111111111111111111111111111111111111"
    }
  end
end
