defmodule TechTree.V1.Chain do
  @moduledoc false

  @node_published_topic0 "0xebe674fa1c2095533bf5dec53f1149fb2b7462e631899d2ea31858576fe1827d"
  @get_header_selector "0xb9615878"
  @tx_hash_regex ~r/^0x[0-9a-f]{64}$/
  @bytes32_regex ~r/^0x[0-9a-f]{64}$/
  @address_regex ~r/^0x[0-9a-f]{40}$/

  @type published_submission :: %{
          node_type: String.t(),
          header: map(),
          manifest_cid: String.t(),
          payload_cid: String.t(),
          tx_hash: String.t(),
          block_number: non_neg_integer(),
          block_time: DateTime.t() | nil,
          chain_id: non_neg_integer(),
          contract_address: String.t(),
          log_index: non_neg_integer()
        }

  @spec fetch_published_submission(map()) ::
          {:ok, published_submission()} | :not_found | {:error, term()}
  def fetch_published_submission(attrs) when is_map(attrs) do
    with {:ok, tx_hash} <- normalize_tx_hash(fetch_value(attrs, "tx_hash")),
         {:ok, cfg} <- config(),
         {:ok, receipt_payload} <- rpc_request(cfg, "eth_getTransactionReceipt", [tx_hash]) do
      case receipt_payload do
        nil ->
          :not_found

        payload when is_map(payload) ->
          parse_submission(cfg, payload, tx_hash, attrs)

        other ->
          {:error, {:invalid_receipt_payload, other}}
      end
    end
  end

  defp parse_submission(cfg, receipt_payload, tx_hash, attrs) do
    with :ok <- validate_receipt_status(receipt_payload),
         {:ok, block_number} <- parse_hex_quantity(map_fetch(receipt_payload, "blockNumber")),
         {:ok, chain_id} <- resolve_chain_id(cfg),
         {:ok, contract_address, log_index, published_log} <-
           find_node_published_log(cfg, map_fetch(receipt_payload, "logs") || []),
         {:ok, header} <- fetch_header(cfg, published_log.id),
         :ok <- verify_expected(attrs, published_log, header),
         {:ok, block_time} <- fetch_block_time(cfg, map_fetch(receipt_payload, "blockNumber")) do
      {:ok,
       %{
         node_type: node_type_name(header["node_type"]),
         header: header,
         manifest_cid: published_log.manifest_cid,
         payload_cid: published_log.payload_cid,
         tx_hash: tx_hash,
         block_number: block_number,
         block_time: block_time,
         chain_id: chain_id,
         contract_address: contract_address,
         log_index: log_index
       }}
    end
  end

  defp find_node_published_log(cfg, logs) when is_list(logs) do
    matching_logs =
      logs
      |> Enum.filter(fn log ->
        is_map(log) and
          same_address?(cfg.registry_address, map_fetch(log, "address")) and
          topic(log, 0) == @node_published_topic0
      end)

    case matching_logs do
      [log] ->
        with :ok <- validate_log_not_removed(log),
             {:ok, log_index} <- parse_hex_quantity(map_fetch(log, "logIndex")),
             {:ok, contract_address} <- normalize_address(map_fetch(log, "address")),
             {:ok, parsed} <- decode_node_published_log(log) do
          {:ok, contract_address, log_index, parsed}
        end

      [] ->
        {:error, :node_published_log_not_found}

      _ ->
        {:error, :ambiguous_node_published_logs}
    end
  end

  defp find_node_published_log(_cfg, _logs), do: {:error, :invalid_logs_payload}

  defp decode_node_published_log(log) do
    with {:ok, id} <- normalize_bytes32(topic(log, 1)),
         {:ok, node_type} <- parse_hex_quantity(topic(log, 2)),
         {:ok, author} <- parse_topic_address(topic(log, 3)),
         {:ok, manifest_cid, payload_cid} <- decode_bytes_pair(map_fetch(log, "data")) do
      {:ok,
       %{
         id: id,
         node_type: node_type,
         author: author,
         manifest_cid: manifest_cid,
         payload_cid: payload_cid
       }}
    end
  end

  defp decode_bytes_pair("0x" <> hex) do
    with {:ok, binary} <- Base.decode16(hex, case: :mixed),
         true <- byte_size(binary) >= 64,
         {:ok, first_offset} <- decode_u256(binary_part(binary, 0, 32)),
         {:ok, second_offset} <- decode_u256(binary_part(binary, 32, 32)),
         {:ok, manifest_cid} <- decode_dynamic_bytes(binary, first_offset),
         {:ok, payload_cid} <- decode_dynamic_bytes(binary, second_offset) do
      {:ok, manifest_cid, payload_cid}
    else
      false -> {:error, :invalid_node_published_data}
      :error -> {:error, :invalid_node_published_data}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_bytes_pair(_value), do: {:error, :invalid_node_published_data}

  defp decode_dynamic_bytes(binary, offset) when is_binary(binary) and is_integer(offset) do
    if offset < 0 or offset + 32 > byte_size(binary) do
      {:error, :invalid_node_published_data}
    else
      with {:ok, length} <- decode_u256(binary_part(binary, offset, 32)),
           true <- offset + 32 + length <= byte_size(binary) do
        {:ok, binary_part(binary, offset + 32, length)}
      else
        false -> {:error, :invalid_node_published_data}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fetch_header(cfg, node_id) do
    call = %{
      "to" => cfg.registry_address,
      "data" => @get_header_selector <> String.trim_leading(node_id, "0x")
    }

    case rpc_request(cfg, "eth_call", [call, "latest"]) do
      {:ok, result} -> decode_header_result(result)
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_header_result("0x" <> hex) do
    with {:ok, binary} <- Base.decode16(hex, case: :mixed),
         true <- byte_size(binary) >= 32 * 8 do
      {:ok,
       %{
         "id" => encode_bytes32(binary, 0),
         "subject_id" => encode_bytes32(binary, 1),
         "aux_id" => encode_bytes32(binary, 2),
         "payload_hash" => "sha256:" <> encode_word_hex(binary, 3),
         "node_type" => decode_word_int(binary, 4),
         "schema_version" => decode_word_int(binary, 5),
         "flags" => decode_word_int(binary, 6),
         "author" => encode_word_address(binary, 7)
       }}
    else
      false -> {:error, :invalid_header_result}
      :error -> {:error, :invalid_header_result}
    end
  end

  defp decode_header_result(_value), do: {:error, :invalid_header_result}

  defp verify_expected(attrs, published_log, header) do
    with :ok <- verify_expected_value("node_id", fetch_value(attrs, "node_id"), published_log.id),
         :ok <-
           verify_expected_value(
             "manifest_cid",
             fetch_value(attrs, "manifest_cid"),
             published_log.manifest_cid
           ),
         :ok <-
           verify_expected_value(
             "payload_cid",
             fetch_value(attrs, "payload_cid"),
             published_log.payload_cid
           ),
         :ok <- verify_expected_header(fetch_value(attrs, "header"), header) do
      verify_expected_value("author", fetch_value(attrs, "author"), header["author"])
    end
  end

  defp verify_expected_header(nil, _header), do: :ok

  defp verify_expected_header(expected, actual) when is_map(expected) do
    normalized = normalize_expected_header(expected)

    mismatches =
      normalized
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.filter(fn {key, value} -> Map.get(actual, key) != value end)

    case mismatches do
      [] ->
        :ok

      [{field, value} | _rest] ->
        {:error, {:header_mismatch, field, value, Map.get(actual, field)}}
    end
  end

  defp verify_expected_header(_expected, _header), do: {:error, :invalid_expected_header}

  defp normalize_expected_header(header) do
    %{
      "id" => fetch_value(header, "id"),
      "subject_id" => fetch_value(header, "subject_id") || fetch_value(header, "subjectId"),
      "aux_id" => fetch_value(header, "aux_id") || fetch_value(header, "auxId"),
      "payload_hash" => fetch_value(header, "payload_hash") || fetch_value(header, "payloadHash"),
      "node_type" => fetch_value(header, "node_type") || fetch_value(header, "nodeType"),
      "schema_version" =>
        fetch_value(header, "schema_version") || fetch_value(header, "schemaVersion"),
      "flags" => fetch_value(header, "flags"),
      "author" => fetch_value(header, "author")
    }
    |> Enum.map(fn {key, value} -> {key, normalize_header_value(key, value)} end)
    |> Map.new()
  end

  defp normalize_header_value(_key, nil), do: nil
  defp normalize_header_value("node_type", value), do: normalize_int(value)
  defp normalize_header_value("schema_version", value), do: normalize_int(value)
  defp normalize_header_value("flags", value), do: normalize_int(value)

  defp normalize_header_value("payload_hash", "sha256:" <> rest) do
    "sha256:" <> String.downcase(rest)
  end

  defp normalize_header_value("payload_hash", "0x" <> raw_hex) when byte_size(raw_hex) == 64 do
    "sha256:" <> String.downcase(raw_hex)
  end

  defp normalize_header_value(_key, "0x" <> _ = value), do: String.downcase(value)
  defp normalize_header_value(_key, value) when is_binary(value), do: value
  defp normalize_header_value(_key, value), do: value

  defp verify_expected_value(_label, nil, _actual), do: :ok

  defp verify_expected_value(label, expected, actual) do
    normalized_expected =
      case expected do
        "0x" <> _ = value -> String.downcase(value)
        value -> value
      end

    normalized_actual =
      case actual do
        "0x" <> _ = value -> String.downcase(value)
        value -> value
      end

    if normalized_expected == normalized_actual do
      :ok
    else
      {:error, {:mismatch, label, normalized_expected, normalized_actual}}
    end
  end

  defp fetch_block_time(cfg, block_number_hex) do
    with {:ok, payload} <- rpc_request(cfg, "eth_getBlockByNumber", [block_number_hex, false]) do
      case payload do
        %{"timestamp" => timestamp_hex} ->
          with {:ok, timestamp} <- parse_hex_quantity(timestamp_hex),
               {:ok, datetime} <- DateTime.from_unix(timestamp) do
            {:ok, datetime}
          else
            _ -> {:ok, nil}
          end

        _ ->
          {:ok, nil}
      end
    end
  end

  defp validate_receipt_status(receipt_payload) do
    case map_fetch(receipt_payload, "status") do
      nil ->
        {:error, :missing_receipt_status}

      value ->
        with {:ok, status} <- parse_hex_quantity(value) do
          if status == 1, do: :ok, else: {:error, {:failed_transaction_receipt, status}}
        end
    end
  end

  defp resolve_chain_id(cfg) do
    with {:ok, chain_id_hex} <- rpc_request(cfg, "eth_chainId", []),
         {:ok, resolved_chain_id} <- parse_hex_quantity(chain_id_hex),
         :ok <- ensure_chain_id_match(normalize_config_chain_id(cfg.chain_id), resolved_chain_id) do
      {:ok, resolved_chain_id}
    end
  end

  defp rpc_request(cfg, method, params) when is_binary(method) and is_list(params) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => method,
      "params" => params
    }

    case cfg.rpc_client.(cfg.rpc_url, payload) do
      {:ok, %{"result" => result}} ->
        {:ok, result}

      {:ok, %{"error" => error}} ->
        {:error, {:rpc_error, error}}

      {:ok, other} ->
        {:error, {:invalid_rpc_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp config do
    cfg = Application.get_env(:tech_tree, :ethereum, [])

    rpc_url = cfg_fetch(cfg, :rpc_url)
    registry_address = cfg_fetch(cfg, :registry_address)

    cond do
      not is_binary(rpc_url) or String.trim(rpc_url) == "" ->
        {:error, {:rpc_config_missing, :rpc_url}}

      not is_binary(registry_address) or String.trim(registry_address) == "" ->
        {:error, {:rpc_config_missing, :registry_address}}

      true ->
        {:ok,
         %{
           rpc_url: rpc_url,
           registry_address: String.downcase(registry_address),
           chain_id: normalize_config_chain_id(cfg_fetch(cfg, :chain_id)),
           request_timeout_ms: cfg_fetch(cfg, :request_timeout_ms) || 5_000,
           rpc_client: cfg_fetch(cfg, :rpc_client) || (&default_rpc_client/2)
         }}
    end
  end

  defp cfg_fetch(cfg, key) when is_list(cfg), do: Keyword.get(cfg, key)

  defp cfg_fetch(cfg, key) when is_map(cfg),
    do: Map.get(cfg, key, Map.get(cfg, Atom.to_string(key)))

  defp cfg_fetch(_cfg, _key), do: nil

  defp normalize_config_chain_id(value) when is_integer(value) and value > 0, do: value

  defp normalize_config_chain_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp normalize_config_chain_id(_value), do: nil

  defp ensure_chain_id_match(nil, _resolved_chain_id), do: :ok
  defp ensure_chain_id_match(chain_id, chain_id), do: :ok

  defp ensure_chain_id_match(configured_chain_id, resolved_chain_id) do
    {:error, {:chain_id_mismatch, configured: configured_chain_id, resolved: resolved_chain_id}}
  end

  defp default_rpc_client(rpc_url, payload) do
    case Req.post(url: rpc_url, json: payload, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:rpc_http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_topic_address("0x" <> raw) when byte_size(raw) == 64 do
    normalize_address("0x" <> String.slice(String.downcase(raw), 24, 40))
  end

  defp parse_topic_address(_value), do: {:error, :invalid_node_published_author}

  defp normalize_tx_hash(value) when is_binary(value) do
    normalized = String.downcase(value)
    if normalized =~ @tx_hash_regex, do: {:ok, normalized}, else: {:error, :invalid_tx_hash}
  end

  defp normalize_tx_hash(_value), do: {:error, :invalid_tx_hash}

  defp normalize_address(value) when is_binary(value) do
    normalized = String.downcase(value)
    if normalized =~ @address_regex, do: {:ok, normalized}, else: {:error, :invalid_address}
  end

  defp normalize_address(_value), do: {:error, :invalid_address}

  defp normalize_bytes32(value) when is_binary(value) do
    normalized = String.downcase(value)
    if normalized =~ @bytes32_regex, do: {:ok, normalized}, else: {:error, :invalid_bytes32}
  end

  defp normalize_bytes32(_value), do: {:error, :invalid_bytes32}

  defp parse_hex_quantity("0x" <> hex) when byte_size(hex) > 0 do
    case Integer.parse(hex, 16) do
      {value, ""} -> {:ok, value}
      _ -> {:error, :invalid_hex_quantity}
    end
  end

  defp parse_hex_quantity(_value), do: {:error, :invalid_hex_quantity}

  defp node_type_name(1), do: "artifact"
  defp node_type_name(2), do: "run"
  defp node_type_name(3), do: "review"
  defp node_type_name(other), do: to_string(other)

  defp decode_u256(binary) when is_binary(binary) and byte_size(binary) == 32 do
    {:ok, :binary.decode_unsigned(binary)}
  end

  defp decode_word_int(binary, index),
    do: :binary.decode_unsigned(binary_part(binary, index * 32, 32))

  defp encode_bytes32(binary, index), do: "0x" <> encode_word_hex(binary, index)

  defp encode_word_hex(binary, index) do
    binary
    |> binary_part(index * 32, 32)
    |> Base.encode16(case: :lower)
  end

  defp encode_word_address(binary, index) do
    word = binary_part(binary, index * 32, 32)
    "0x" <> (word |> binary_part(12, 20) |> Base.encode16(case: :lower))
  end

  defp normalize_int(value) when is_integer(value), do: value

  defp normalize_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> value
    end
  end

  defp normalize_int(value), do: value

  defp same_address?(expected, value) when is_binary(expected) and is_binary(value),
    do: String.downcase(expected) == String.downcase(value)

  defp same_address?(_expected, _value), do: false

  defp validate_log_not_removed(%{"removed" => true}), do: {:error, :removed_node_published_log}
  defp validate_log_not_removed(_log), do: :ok

  defp topic(log, index) when is_map(log) and is_integer(index) do
    log
    |> Map.get("topics", [])
    |> Enum.at(index)
    |> case do
      value when is_binary(value) -> String.downcase(value)
      _ -> nil
    end
  end

  defp map_fetch(map, key) when is_map(map), do: Map.get(map, key)
  defp map_fetch(_map, _key), do: nil

  defp fetch_value(map, key) when is_map(map) do
    Map.get(map, key) ||
      case key do
        "tx_hash" -> Map.get(map, :tx_hash)
        "node_id" -> Map.get(map, :node_id)
        "manifest_cid" -> Map.get(map, :manifest_cid)
        "payload_cid" -> Map.get(map, :payload_cid)
        "author" -> Map.get(map, :author)
        "header" -> Map.get(map, :header)
        "id" -> Map.get(map, :id)
        "subject_id" -> Map.get(map, :subject_id)
        "subjectId" -> Map.get(map, :subjectId)
        "aux_id" -> Map.get(map, :aux_id)
        "auxId" -> Map.get(map, :auxId)
        "payload_hash" -> Map.get(map, :payload_hash)
        "payloadHash" -> Map.get(map, :payloadHash)
        "node_type" -> Map.get(map, :node_type)
        "nodeType" -> Map.get(map, :nodeType)
        "schema_version" -> Map.get(map, :schema_version)
        "schemaVersion" -> Map.get(map, :schemaVersion)
        "flags" -> Map.get(map, :flags)
        _ -> nil
      end
  end
end
