defmodule TechTree.V1ChainSupport do
  @moduledoc false

  @event_topic0 "0xebe674fa1c2095533bf5dec53f1149fb2b7462e631899d2ea31858576fe1827d"
  @get_header_selector "0xb9615878"

  def load_fixture!(name) do
    dist_dir =
      Path.expand("../../core/fixtures/golden/#{name}/dist", __DIR__)

    %{
      manifest: dist_dir |> Path.join(manifest_name(name)) |> read_json!(),
      payload_index: dist_dir |> Path.join("payload.index.json") |> read_json!(),
      header: dist_dir |> Path.join("node-header.json") |> read_json!()
    }
  end

  def rpc_client_for_submission(opts) do
    receipt = fetch_opt!(opts, :receipt)
    header = fetch_opt!(opts, :header)
    chain_id_hex = fetch_opt(opts, :chain_id_hex, "0x2105")
    block_hex = fetch_opt(opts, :block_number_hex, "0x2a")
    block_timestamp_hex = fetch_opt(opts, :block_timestamp_hex, "0x65f0abc0")

    fn _rpc_url, payload ->
      case payload["method"] do
        "eth_getTransactionReceipt" ->
          {:ok, %{"jsonrpc" => "2.0", "id" => payload["id"], "result" => receipt}}

        "eth_chainId" ->
          {:ok, %{"jsonrpc" => "2.0", "id" => payload["id"], "result" => chain_id_hex}}

        "eth_getBlockByNumber" ->
          if payload["params"] != [block_hex, false] do
            raise "unexpected block request #{inspect(payload["params"])}"
          end

          {:ok,
           %{
             "jsonrpc" => "2.0",
             "id" => payload["id"],
             "result" => %{"timestamp" => block_timestamp_hex}
           }}

        "eth_call" ->
          expected_data = @get_header_selector <> String.trim_leading(header["id"], "0x")

          expected_registry = fetch_opt!(opts, :registry_address)

          if payload["params"] != [
               %{"to" => expected_registry, "data" => expected_data},
               "latest"
             ] do
            raise "unexpected eth_call params #{inspect(payload["params"])}"
          end

          {:ok,
           %{
             "jsonrpc" => "2.0",
             "id" => payload["id"],
             "result" => encode_header_result(header)
           }}

        other ->
          raise "unexpected rpc method #{inspect(other)}"
      end
    end
  end

  def build_receipt(header, opts \\ []) do
    registry_address = fetch_opt!(opts, :registry_address)
    manifest_cid = fetch_opt!(opts, :manifest_cid)
    payload_cid = fetch_opt!(opts, :payload_cid)
    block_number_hex = fetch_opt(opts, :block_number_hex, "0x2a")
    log_index_hex = fetch_opt(opts, :log_index_hex, "0x3")

    %{
      "blockNumber" => block_number_hex,
      "status" => fetch_opt(opts, :status, "0x1"),
      "logs" =>
        fetch_opt(opts, :logs, [
          %{
            "address" => registry_address,
            "topics" => [
              @event_topic0,
              header["id"],
              encode_uint256(header["node_type"]),
              encode_address_topic(header["author"])
            ],
            "data" => encode_bytes_pair(manifest_cid, payload_cid),
            "logIndex" => log_index_hex,
            "removed" => fetch_opt(opts, :removed, false)
          }
        ])
    }
  end

  def gateway_child_spec(responses) do
    port = 40_000 + rem(System.unique_integer([:positive]), 10_000)
    {{TechTree.TestIpfsGatewayServer, {responses, port}}, "http://127.0.0.1:#{port}"}
  end

  def encode_header_result(header) do
    "0x" <>
      Enum.join([
        trim_0x(header["id"]),
        trim_0x(header["subject_id"]),
        trim_0x(header["aux_id"]),
        String.replace_prefix(header["payload_hash"], "sha256:", ""),
        encode_uint256_word(header["node_type"]),
        encode_uint256_word(header["schema_version"]),
        encode_uint256_word(header["flags"]),
        encode_address_word(header["author"])
      ])
  end

  def encode_bytes_pair(first, second) do
    first_bin = IO.iodata_to_binary(first)
    second_bin = IO.iodata_to_binary(second)
    first_section = encode_dynamic_bytes(first_bin)
    second_offset = 64 + byte_size(first_section)

    "0x" <>
      encode_uint256_word(64) <>
      encode_uint256_word(second_offset) <>
      Base.encode16(first_section <> encode_dynamic_bytes(second_bin), case: :lower)
  end

  def manifest_name("artifact_" <> _), do: "artifact.manifest.json"
  def manifest_name("run_" <> _), do: "run.manifest.json"
  def manifest_name("review_" <> _), do: "review.manifest.json"

  defp encode_dynamic_bytes(binary) do
    padding = rem(32 - rem(byte_size(binary), 32), 32)
    <<encode_u256(byte_size(binary))::binary, binary::binary, 0::size(padding * 8)>>
  end

  defp encode_u256(value),
    do:
      <<0::size(256 - 8 * byte_size(:binary.encode_unsigned(value))),
        :binary.encode_unsigned(value)::binary>>

  defp encode_uint256(value), do: "0x" <> encode_uint256_word(value)
  defp encode_uint256_word(value), do: Base.encode16(encode_u256(value), case: :lower)

  defp encode_address_word("0x" <> raw_hex) do
    String.duplicate("0", 24) <> String.downcase(raw_hex)
  end

  defp encode_address_topic(address), do: "0x" <> encode_address_word(address)

  defp trim_0x("0x" <> raw_hex), do: String.downcase(raw_hex)

  defp read_json!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp fetch_opt(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
  defp fetch_opt(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)

  defp fetch_opt!(opts, key) when is_list(opts), do: Keyword.fetch!(opts, key)
  defp fetch_opt!(opts, key) when is_map(opts), do: Map.fetch!(opts, key)
end
