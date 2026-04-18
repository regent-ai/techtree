defmodule TechTree.EthereumTest do
  use ExUnit.Case, async: false

  alias TechTree.Ethereum

  @valid_create_node_params %{
    node_id: 101,
    parent_id: 0,
    creator: "0x1111111111111111111111111111111111111111",
    manifest_uri: "ipfs://manifest-101",
    manifest_hash: String.duplicate("ab", 32),
    kind: 2
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

  test "create_node falls back to stub mode when rpc settings are absent" do
    Application.put_env(:tech_tree, :ethereum, mode: :auto, rpc_url: nil, registry_address: nil)

    assert {:ok, tx_hash} = Ethereum.create_node(@valid_create_node_params)
    assert tx_hash =~ ~r/^0x[0-9a-f]{64}$/
  end

  test "create_node normalizes manifest hash and submits cast transaction in rpc mode" do
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
             Ethereum.create_node(%{
               @valid_create_node_params
               | manifest_hash: String.duplicate("CD", 32)
             })

    assert_receive {:cast_invocation, "cast", args}
    assert Enum.member?(args, "createNode(uint256,uint256,address,string,bytes32,uint8)")
    assert Enum.member?(args, "0x" <> String.duplicate("cd", 32))
  end

  test "create_node in explicit rpc mode surfaces missing writer key config" do
    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: "0x2222222222222222222222222222222222222222",
      writer_private_key: nil
    )

    assert {:error, {:rpc_config_missing, :writer_private_key}} =
             Ethereum.create_node(@valid_create_node_params)
  end

  test "fetch_receipt returns :not_found for pending rpc transaction" do
    parent = self()

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: "0x3333333333333333333333333333333333333333",
      writer_private_key: "0x" <> String.duplicate("2", 64),
      rpc_client: fn _rpc_url, payload ->
        send(parent, {:rpc_method, payload["method"]})
        {:ok, %{"jsonrpc" => "2.0", "id" => payload["id"], "result" => nil}}
      end
    )

    assert :not_found = Ethereum.fetch_receipt("0x" <> String.duplicate("9", 64), nil)
    assert_receive {:rpc_method, "eth_getTransactionReceipt"}
  end

  test "fetch_receipt parses block, chain id, contract address, and log index in rpc mode" do
    registry = "0x4444444444444444444444444444444444444444"

    node_created_topic0 = node_created_topic0()

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: registry,
      writer_private_key: "0x" <> String.duplicate("3", 64),
      chain_id: nil,
      rpc_client: fn _rpc_url, payload ->
        case payload["method"] do
          "eth_getTransactionReceipt" ->
            {:ok,
             %{
               "jsonrpc" => "2.0",
               "id" => payload["id"],
               "result" => %{
                 "blockNumber" => "0x2a",
                 "status" => "0x1",
                 "logs" => [
                   %{
                     "address" => "0x5555555555555555555555555555555555555555",
                     "topics" => [node_created_topic0],
                     "logIndex" => "0x0"
                   },
                   %{
                     "address" => String.upcase(registry),
                     "topics" => [node_created_topic0],
                     "logIndex" => "0x3"
                   }
                 ]
               }
             }}

          "eth_chainId" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => payload["id"], "result" => "0x14a34"}}
        end
      end
    )

    assert {:ok, receipt} = Ethereum.fetch_receipt("0x" <> String.duplicate("8", 64), nil)
    assert receipt.block_number == 42
    assert receipt.chain_id == 84_532
    assert receipt.contract_address == registry
    assert receipt.log_index == 3
  end

  test "fetch_receipt in explicit rpc mode surfaces missing registry config" do
    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: nil,
      writer_private_key: "0x" <> String.duplicate("3", 64)
    )

    assert {:error, {:rpc_config_missing, :registry_address}} =
             Ethereum.fetch_receipt("0x" <> String.duplicate("7", 64), nil)
  end

  test "fetch_receipt rejects failed receipt status" do
    registry = "0x4444444444444444444444444444444444444444"

    node_created_topic0 = node_created_topic0()

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: registry,
      writer_private_key: "0x" <> String.duplicate("4", 64),
      rpc_client: fn _rpc_url, payload ->
        case payload["method"] do
          "eth_getTransactionReceipt" ->
            {:ok,
             %{
               "jsonrpc" => "2.0",
               "id" => payload["id"],
               "result" => %{
                 "blockNumber" => "0x2a",
                 "status" => "0x0",
                 "logs" => [
                   %{
                     "address" => registry,
                     "topics" => [node_created_topic0],
                     "logIndex" => "0x1"
                   }
                 ]
               }
             }}

          "eth_chainId" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => payload["id"], "result" => "0x14a34"}}
        end
      end
    )

    assert {:error, {:failed_transaction_receipt, 0}} =
             Ethereum.fetch_receipt("0x" <> String.duplicate("6", 64), nil)
  end

  test "fetch_receipt rejects ambiguous node-created logs" do
    registry = "0x4444444444444444444444444444444444444444"

    node_created_topic0 = node_created_topic0()

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: registry,
      writer_private_key: "0x" <> String.duplicate("5", 64),
      rpc_client: fn _rpc_url, payload ->
        case payload["method"] do
          "eth_getTransactionReceipt" ->
            {:ok,
             %{
               "jsonrpc" => "2.0",
               "id" => payload["id"],
               "result" => %{
                 "blockNumber" => "0x2a",
                 "status" => "0x1",
                 "logs" => [
                   %{
                     "address" => registry,
                     "topics" => [node_created_topic0],
                     "logIndex" => "0x1"
                   },
                   %{
                     "address" => String.upcase(registry),
                     "topics" => [node_created_topic0],
                     "logIndex" => "0x2"
                   }
                 ]
               }
             }}

          "eth_chainId" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => payload["id"], "result" => "0x14a34"}}
        end
      end
    )

    assert {:error, :ambiguous_node_created_logs} =
             Ethereum.fetch_receipt("0x" <> String.duplicate("5", 64), nil)
  end

  test "fetch_receipt rejects removed node-created logs" do
    registry = "0x4444444444444444444444444444444444444444"

    node_created_topic0 = node_created_topic0()

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: registry,
      writer_private_key: "0x" <> String.duplicate("6", 64),
      rpc_client: fn _rpc_url, payload ->
        case payload["method"] do
          "eth_getTransactionReceipt" ->
            {:ok,
             %{
               "jsonrpc" => "2.0",
               "id" => payload["id"],
               "result" => %{
                 "blockNumber" => "0x2a",
                 "status" => "0x1",
                 "logs" => [
                   %{
                     "address" => registry,
                     "topics" => [node_created_topic0],
                     "logIndex" => "0x1",
                     "removed" => true
                   }
                 ]
               }
             }}

          "eth_chainId" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => payload["id"], "result" => "0x14a34"}}
        end
      end
    )

    assert {:error, :node_created_log_removed} =
             Ethereum.fetch_receipt("0x" <> String.duplicate("4", 64), nil)
  end

  test "fetch_receipt rejects configured chain id mismatch" do
    registry = "0x4444444444444444444444444444444444444444"

    node_created_topic0 = node_created_topic0()

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: registry,
      writer_private_key: "0x" <> String.duplicate("7", 64),
      chain_id: 8_453,
      rpc_client: fn _rpc_url, payload ->
        case payload["method"] do
          "eth_getTransactionReceipt" ->
            {:ok,
             %{
               "jsonrpc" => "2.0",
               "id" => payload["id"],
               "result" => %{
                 "blockNumber" => "0x2a",
                 "status" => "0x1",
                 "logs" => [
                   %{
                     "address" => registry,
                     "topics" => [node_created_topic0],
                     "logIndex" => "0x1"
                   }
                 ]
               }
             }}

          "eth_chainId" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => payload["id"], "result" => "0x14a34"}}
        end
      end
    )

    assert {:error, {:chain_id_mismatch, [configured: 8_453, resolved: 84_532]}} =
             Ethereum.fetch_receipt("0x" <> String.duplicate("3", 64), nil)
  end

  test "fetch_receipt with verification rejects node-created field mismatch" do
    registry = "0x4444444444444444444444444444444444444444"
    creator = "0x1111111111111111111111111111111111111111"
    tx_hash = "0x" <> String.duplicate("2", 64)

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: registry,
      writer_private_key: "0x" <> String.duplicate("8", 64),
      rpc_client: fn _rpc_url, payload ->
        case payload["method"] do
          "eth_getTransactionReceipt" ->
            {:ok,
             %{
               "jsonrpc" => "2.0",
               "id" => payload["id"],
               "result" => %{
                 "blockNumber" => "0x2a",
                 "status" => "0x1",
                 "logs" => [
                   %{
                     "address" => registry,
                     "topics" => [
                       node_created_topic0(),
                       topic_uint(901),
                       topic_uint(33),
                       topic_address(creator)
                     ],
                     "data" =>
                       node_created_data(
                         anchored_by: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                         manifest_uri: "ipfs://manifest-901",
                         manifest_hash: "0x" <> String.duplicate("ab", 32),
                         kind: 2,
                         created_at: 700
                       ),
                     "logIndex" => "0x1"
                   }
                 ]
               }
             }}

          "eth_chainId" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => payload["id"], "result" => "0x14a34"}}
        end
      end
    )

    assert {:error, {:node_created_log_mismatch, :node_id, 900, 901}} =
             Ethereum.fetch_receipt(tx_hash, %{
               node_id: 900,
               parent_id: 33,
               creator: creator,
               manifest_hash: String.duplicate("ab", 32),
               kind: 2
             })
  end

  test "fetch_receipt with verification accepts strict node-created field match" do
    registry = "0x4444444444444444444444444444444444444444"
    creator = "0x1111111111111111111111111111111111111111"
    tx_hash = "0x" <> String.duplicate("1", 64)

    Application.put_env(:tech_tree, :ethereum,
      mode: :rpc,
      rpc_url: "http://127.0.0.1:8545",
      registry_address: registry,
      writer_private_key: "0x" <> String.duplicate("9", 64),
      rpc_client: fn _rpc_url, payload ->
        case payload["method"] do
          "eth_getTransactionReceipt" ->
            {:ok,
             %{
               "jsonrpc" => "2.0",
               "id" => payload["id"],
               "result" => %{
                 "blockNumber" => "0x2a",
                 "status" => "0x1",
                 "logs" => [
                   %{
                     "address" => String.upcase(registry),
                     "topics" => [
                       node_created_topic0(),
                       topic_uint(1201),
                       topic_uint(0),
                       topic_address(String.upcase(creator))
                     ],
                     "data" =>
                       node_created_data(
                         anchored_by: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                         manifest_uri: "ipfs://manifest-1201",
                         manifest_hash: "0x" <> String.duplicate("cd", 32),
                         kind: 7,
                         created_at: 701
                       ),
                     "logIndex" => "0x3"
                   }
                 ]
               }
             }}

          "eth_chainId" ->
            {:ok, %{"jsonrpc" => "2.0", "id" => payload["id"], "result" => "0x14a34"}}
        end
      end
    )

    assert {:ok, receipt} =
             Ethereum.fetch_receipt(tx_hash, %{
               node_id: 1201,
               parent_id: 0,
               creator: creator,
               manifest_hash: String.duplicate("CD", 32),
               kind: 7
             })

    assert receipt.block_number == 42
    assert receipt.chain_id == 84_532
    assert receipt.contract_address == registry
    assert receipt.log_index == 3
  end

  defp node_created_topic0 do
    "0x90daf5db66aff563cb61be4aa2769376ac8cd6eb0dddb7f8d1b87d05acb8946c"
  end

  defp topic_uint(value) do
    "0x" <> String.pad_leading(Integer.to_string(value, 16), 64, "0")
  end

  defp topic_address(address) do
    "0x" <> String.pad_leading(strip_0x(address), 64, "0")
  end

  defp node_created_data(opts) do
    manifest_uri = Keyword.fetch!(opts, :manifest_uri)
    manifest_hash = Keyword.fetch!(opts, :manifest_hash)
    anchored_by = Keyword.fetch!(opts, :anchored_by)
    kind = Keyword.fetch!(opts, :kind)
    created_at = Keyword.fetch!(opts, :created_at)

    uri_hex = Elixir.Base.encode16(manifest_uri, case: :lower)
    uri_word_size = div(byte_size(uri_hex) + 63, 64)
    uri_tail = String.pad_trailing(uri_hex, uri_word_size * 64, "0")

    "0x" <>
      pad_word(strip_0x(anchored_by)) <>
      pad_word(Integer.to_string(160, 16)) <>
      pad_word(strip_0x(manifest_hash)) <>
      pad_word(Integer.to_string(kind, 16)) <>
      pad_word(Integer.to_string(created_at, 16)) <>
      pad_word(Integer.to_string(byte_size(manifest_uri), 16)) <>
      uri_tail
  end

  defp pad_word(hex_without_prefix) do
    String.pad_leading(String.downcase(hex_without_prefix), 64, "0")
  end

  defp strip_0x("0x" <> rest), do: rest
  defp strip_0x("0X" <> rest), do: rest
  defp strip_0x(value), do: value
end
