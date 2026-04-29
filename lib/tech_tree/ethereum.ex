defmodule TechTree.Ethereum do
  @moduledoc false

  @required_create_node_keys [
    :node_id,
    :parent_id,
    :creator,
    :manifest_uri,
    :manifest_hash,
    :kind
  ]

  @type create_node_params :: %{
          required(:node_id) => integer(),
          required(:parent_id) => integer(),
          required(:creator) => String.t(),
          required(:manifest_uri) => String.t(),
          required(:manifest_hash) => String.t(),
          required(:kind) => non_neg_integer()
        }

  @type receipt :: %{
          block_number: non_neg_integer(),
          chain_id: non_neg_integer(),
          contract_address: String.t(),
          log_index: non_neg_integer()
        }

  @type node_created_verification :: %{
          required(:node_id) => non_neg_integer(),
          required(:parent_id) => non_neg_integer(),
          required(:creator) => String.t(),
          required(:manifest_hash) => String.t(),
          required(:kind) => non_neg_integer()
        }

  @default_chain_id 84_532
  @default_contract_address "0x0000000000000000000000000000000000000000"
  @create_node_signature "createNode(uint256,uint256,address,string,bytes32,uint8)"
  # Ethereum logs use Keccak-256, not SHA3-256.
  @node_created_topic0 "0x90daf5db66aff563cb61be4aa2769376ac8cd6eb0dddb7f8d1b87d05acb8946c"
  @tx_hash_exact_regex ~r/^0x[0-9a-fA-F]{64}$/
  @tx_hash_in_text_regex ~r/0x[0-9a-fA-F]{64}/
  @address_regex ~r/^0x[0-9a-fA-F]{40}$/
  @hex32_regex ~r/^[0-9a-fA-F]{64}$/
  @hex_word_with_prefix_regex ~r/^0x[0-9a-fA-F]{64}$/
  @private_key_regex ~r/^(0x)?[0-9a-fA-F]{64}$/

  @spec create_node(create_node_params()) :: {:ok, String.t()} | {:error, term()}
  def create_node(params) when is_map(params) do
    with :ok <- validate_create_node_params(params) do
      case config().mode do
        :stub ->
          {:ok, stub_tx_hash()}

        :rpc ->
          create_node_rpc(params)
      end
    end
  end

  def create_node(_params), do: {:error, :invalid_params}

  @spec fetch_receipt(String.t(), node_created_verification() | nil) ::
          {:ok, receipt()} | :not_found | {:error, term()}
  def fetch_receipt(tx_hash, verification_input) do
    cfg = config()

    case cfg.mode do
      :stub ->
        fetch_receipt_stub(tx_hash, cfg)

      :rpc ->
        with {:ok, verification} <- normalize_node_created_verification(verification_input) do
          fetch_receipt_rpc(tx_hash, cfg, verification)
        end
    end
  end

  @spec validate_create_node_params(map()) ::
          :ok | {:error, {:missing_param, atom()} | {:invalid_param, atom()}}
  defp validate_create_node_params(params) do
    Enum.reduce_while(@required_create_node_keys, :ok, fn key, _acc ->
      case Map.get(params, key) do
        value when is_binary(value) and byte_size(value) > 0 -> {:cont, :ok}
        value when is_integer(value) -> {:cont, :ok}
        nil -> {:halt, {:error, {:missing_param, key}}}
        _ -> {:halt, {:error, {:invalid_param, key}}}
      end
    end)
  end

  @spec create_node_rpc(create_node_params()) :: {:ok, String.t()} | {:error, term()}
  defp create_node_rpc(params) do
    cfg = config()

    with :ok <- ensure_rpc_create_node_config(cfg),
         {:ok, node_id} <- normalize_uint(Map.fetch!(params, :node_id), :node_id),
         {:ok, parent_id} <- normalize_uint(Map.fetch!(params, :parent_id), :parent_id),
         {:ok, creator} <- normalize_address(Map.fetch!(params, :creator)),
         {:ok, manifest_uri} <-
           normalize_non_empty_string(Map.fetch!(params, :manifest_uri), :manifest_uri),
         {:ok, manifest_hash} <- normalize_manifest_hash(Map.fetch!(params, :manifest_hash)),
         {:ok, writer_private_key} <- normalize_private_key(cfg.writer_private_key),
         {:ok, kind} <- normalize_uint8(Map.fetch!(params, :kind)),
         {:ok, output} <-
           run_cast(
             cfg,
             [
               "send",
               "--async",
               "--rpc-url",
               cfg.rpc_url,
               "--private-key",
               writer_private_key,
               cfg.registry_address,
               @create_node_signature,
               Integer.to_string(node_id),
               Integer.to_string(parent_id),
               creator,
               manifest_uri,
               manifest_hash,
               Integer.to_string(kind)
             ]
           ) do
      extract_tx_hash(output)
    end
  end

  @spec fetch_receipt_stub(String.t(), map()) :: {:ok, receipt()} | :not_found | {:error, term()}
  defp fetch_receipt_stub(tx_hash, cfg) do
    cond do
      not is_binary(tx_hash) ->
        {:error, :invalid_tx_hash}

      String.ends_with?(tx_hash, "pending") ->
        :not_found

      validate_tx_hash(tx_hash) != :ok ->
        {:error, :invalid_tx_hash}

      true ->
        {:ok,
         %{
           block_number: 0,
           chain_id: cfg.chain_id || @default_chain_id,
           contract_address: cfg.registry_address || @default_contract_address,
           log_index: 0
         }}
    end
  end

  @spec fetch_receipt_rpc(String.t(), map(), node_created_verification() | nil) ::
          {:ok, receipt()} | :not_found | {:error, term()}
  defp fetch_receipt_rpc(tx_hash, cfg, verification) do
    with :ok <- ensure_rpc_receipt_config(cfg),
         :ok <- validate_tx_hash(tx_hash),
         {:ok, receipt_payload} <- rpc_request(cfg, "eth_getTransactionReceipt", [tx_hash]) do
      case receipt_payload do
        nil ->
          :not_found

        payload when is_map(payload) ->
          parse_receipt(cfg, payload, verification)

        other ->
          {:error, {:invalid_receipt_payload, other}}
      end
    end
  end

  @spec parse_receipt(map(), map(), node_created_verification() | nil) ::
          {:ok, receipt()} | {:error, term()}
  defp parse_receipt(cfg, receipt_payload, verification) do
    with :ok <- validate_receipt_status(receipt_payload),
         {:ok, block_number} <- parse_hex_quantity(map_fetch(receipt_payload, "blockNumber")),
         {:ok, chain_id} <- resolve_chain_id(cfg),
         {:ok, log} <- find_node_created_log(cfg, map_fetch(receipt_payload, "logs") || []),
         :ok <- validate_node_created_log(log),
         :ok <- verify_node_created_log(log, verification),
         {:ok, log_index} <- parse_hex_quantity(map_fetch(log, "logIndex")),
         {:ok, contract_address} <- parse_log_address(log) do
      {:ok,
       %{
         block_number: block_number,
         chain_id: chain_id,
         contract_address: contract_address,
         log_index: log_index
       }}
    end
  end

  @spec find_node_created_log(map(), list()) :: {:ok, map()} | {:error, term()}
  defp find_node_created_log(cfg, logs) when is_list(logs) do
    matching_logs =
      logs
      |> Enum.filter(fn log ->
        is_map(log) and
          topic0(log) == @node_created_topic0 and
          same_address?(cfg.registry_address, map_fetch(log, "address"))
      end)

    case matching_logs do
      [log] -> {:ok, log}
      [] -> {:error, :node_created_log_not_found}
      _ -> {:error, :ambiguous_node_created_logs}
    end
  end

  defp find_node_created_log(_cfg, _logs), do: {:error, :invalid_logs_payload}

  @spec resolve_chain_id(map()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp resolve_chain_id(cfg) do
    with {:ok, chain_id_hex} <- rpc_request(cfg, "eth_chainId", []),
         {:ok, chain_id} <- parse_hex_quantity(chain_id_hex),
         :ok <- ensure_chain_id_match(cfg.chain_id, chain_id) do
      {:ok, chain_id}
    end
  end

  @spec run_cast(map(), [String.t()]) :: {:ok, String.t()} | {:error, term()}
  defp run_cast(cfg, args) do
    cast_runner = cfg.cast_runner

    result =
      if is_function(cast_runner, 2) do
        cast_runner.(cfg.cast_bin, args)
      else
        run_cmd_with_timeout(cfg.cast_bin, args, 30_000)
      end

    case result do
      {output, 0} when is_binary(output) ->
        {:ok, output}

      {output, status} when is_integer(status) and is_binary(output) ->
        {:error, {:cast_failed, status, String.trim(output)}}

      other ->
        {:error, {:invalid_cast_result, other}}
    end
  rescue
    error ->
      {:error, {:cast_exec_failed, Exception.message(error)}}
  end

  defp run_cmd_with_timeout(command, args, timeout_ms) do
    task = Task.async(fn -> System.cmd(command, args, stderr_to_stdout: true) end)

    receive do
      {ref, result} when ref == task.ref ->
        Process.demonitor(task.ref, [:flush])
        result

      {:DOWN, ref, :process, _pid, reason} when ref == task.ref ->
        {"command failed: #{inspect(reason)}", 1}
    after
      timeout_ms ->
        Task.shutdown(task, :brutal_kill)
        {"command timed out", 124}
    end
  end

  @spec extract_tx_hash(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp extract_tx_hash(output) when is_binary(output) do
    case Regex.run(@tx_hash_in_text_regex, output) do
      [tx_hash] -> {:ok, String.downcase(tx_hash)}
      _ -> {:error, {:tx_hash_not_found, String.trim(output)}}
    end
  end

  @spec rpc_request(map(), String.t(), list()) :: {:ok, term()} | {:error, term()}
  defp rpc_request(cfg, method, params) when is_binary(method) and is_list(params) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => method,
      "params" => params
    }

    with {:ok, response} <- rpc_post(cfg, payload) do
      cond do
        is_map(response) and is_map(response["error"]) ->
          {:error, {:rpc_error, method, response["error"]}}

        is_map(response) and Map.has_key?(response, "result") ->
          {:ok, response["result"]}

        true ->
          {:error, {:invalid_rpc_response, method, response}}
      end
    end
  end

  @spec rpc_post(map(), map()) :: {:ok, map()} | {:error, term()}
  defp rpc_post(cfg, payload) do
    rpc_client = cfg.rpc_client

    if is_function(rpc_client, 2) do
      rpc_client.(cfg.rpc_url, payload)
    else
      do_req_rpc_post(cfg, payload)
    end
  end

  @spec do_req_rpc_post(map(), map()) :: {:ok, map()} | {:error, term()}
  defp do_req_rpc_post(cfg, payload) do
    request =
      Req.new(
        url: cfg.rpc_url,
        json: payload
      )
      |> maybe_merge_req_options(cfg.req_options)

    case Req.post(request) do
      {:ok, %Req.Response{status: status, body: body}}
      when status in 200..299 and is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec maybe_merge_req_options(Req.Request.t(), list() | nil) :: Req.Request.t()
  defp maybe_merge_req_options(request, opts) when is_list(opts), do: Req.merge(request, opts)
  defp maybe_merge_req_options(request, _opts), do: request

  @spec normalize_manifest_hash(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp normalize_manifest_hash(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.replace_prefix("0x", "")
      |> String.replace_prefix("0X", "")

    if Regex.match?(@hex32_regex, normalized) do
      {:ok, "0x" <> String.downcase(normalized)}
    else
      {:error, {:invalid_manifest_hash, value}}
    end
  end

  defp normalize_manifest_hash(_), do: {:error, {:invalid_manifest_hash, :not_binary}}

  @spec normalize_private_key(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp normalize_private_key(private_key) when is_binary(private_key) do
    normalized = String.trim(private_key)

    if Regex.match?(@private_key_regex, normalized) do
      if String.starts_with?(normalized, "0x") or String.starts_with?(normalized, "0X") do
        {:ok,
         "0x" <>
           String.downcase(String.trim_leading(normalized, "0x") |> String.trim_leading("0X"))}
      else
        {:ok, "0x" <> String.downcase(normalized)}
      end
    else
      {:error, :invalid_writer_private_key}
    end
  end

  defp normalize_private_key(_), do: {:error, :invalid_writer_private_key}

  @spec normalize_address(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp normalize_address(address) when is_binary(address) do
    normalized = String.downcase(String.trim(address))

    if Regex.match?(@address_regex, normalized) do
      {:ok, normalized}
    else
      {:error, {:invalid_address, address}}
    end
  end

  defp normalize_address(_), do: {:error, {:invalid_address, :not_binary}}

  @spec normalize_address_value(term()) :: String.t() | nil
  defp normalize_address_value(address) when is_binary(address) do
    normalized = String.downcase(String.trim(address))
    if Regex.match?(@address_regex, normalized), do: normalized, else: nil
  end

  defp normalize_address_value(_), do: nil

  @spec same_address?(String.t() | nil, term()) :: boolean()
  defp same_address?(nil, _other), do: false

  defp same_address?(expected, actual) when is_binary(expected) do
    case normalize_address_value(actual) do
      nil -> false
      normalized_actual -> normalized_actual == expected
    end
  end

  @spec normalize_uint(term(), atom()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp normalize_uint(value, _field) when is_integer(value) and value >= 0, do: {:ok, value}
  defp normalize_uint(_value, field), do: {:error, {:invalid_param, field}}

  @spec normalize_non_empty_string(term(), atom()) :: {:ok, String.t()} | {:error, term()}
  defp normalize_non_empty_string(value, field) when is_binary(value) do
    if String.trim(value) == "", do: {:error, {:invalid_param, field}}, else: {:ok, value}
  end

  defp normalize_non_empty_string(_value, field), do: {:error, {:invalid_param, field}}

  @spec normalize_uint8(term()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp normalize_uint8(value) when is_integer(value) and value >= 0 and value <= 255,
    do: {:ok, value}

  defp normalize_uint8(_value), do: {:error, {:invalid_param, :kind}}

  @spec parse_hex_quantity(term()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp parse_hex_quantity(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp parse_hex_quantity("0x" <> hex) when byte_size(hex) > 0 do
    case Integer.parse(hex, 16) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> {:error, {:invalid_hex_quantity, value: "0x" <> hex}}
    end
  end

  defp parse_hex_quantity("0X" <> hex), do: parse_hex_quantity("0x" <> hex)

  defp parse_hex_quantity(value), do: {:error, {:invalid_hex_quantity, value: value}}

  @spec validate_receipt_status(map()) :: :ok | {:error, term()}
  defp validate_receipt_status(receipt_payload) do
    case map_fetch(receipt_payload, "status") do
      nil ->
        {:error, :missing_receipt_status}

      status_value ->
        with {:ok, status} <- parse_hex_quantity(status_value) do
          if status == 1 do
            :ok
          else
            {:error, {:failed_transaction_receipt, status}}
          end
        end
    end
  end

  @spec validate_node_created_log(map()) :: :ok | {:error, term()}
  defp validate_node_created_log(log) when is_map(log) do
    case map_fetch(log, "removed") do
      true -> {:error, :node_created_log_removed}
      _ -> :ok
    end
  end

  defp validate_node_created_log(_log), do: {:error, :invalid_node_created_log}

  @spec verify_node_created_log(map(), node_created_verification() | nil) ::
          :ok | {:error, term()}
  defp verify_node_created_log(_log, nil), do: :ok

  defp verify_node_created_log(log, verification) when is_map(log) and is_map(verification) do
    with {:ok, decoded} <- decode_node_created_log(log),
         :ok <- ensure_log_field_match(:node_id, verification.node_id, decoded.node_id),
         :ok <- ensure_log_field_match(:parent_id, verification.parent_id, decoded.parent_id),
         :ok <- ensure_log_field_match(:creator, verification.creator, decoded.creator),
         :ok <-
           ensure_log_field_match(
             :manifest_hash,
             verification.manifest_hash,
             decoded.manifest_hash
           ) do
      ensure_log_field_match(:kind, verification.kind, decoded.kind)
    end
  end

  defp verify_node_created_log(_log, _verification),
    do: {:error, :invalid_node_created_verification}

  @spec decode_node_created_log(map()) ::
          {:ok,
           %{
             node_id: non_neg_integer(),
             parent_id: non_neg_integer(),
             creator: String.t(),
             manifest_hash: String.t(),
             kind: non_neg_integer()
           }}
          | {:error, term()}
  defp decode_node_created_log(log) do
    with {:ok, topics} <- decode_node_created_topics(log),
         {:ok, data_hex} <- decode_node_created_data(log),
         {:ok, node_id} <- parse_topic_uint(Enum.at(topics, 1)),
         {:ok, parent_id} <- parse_topic_uint(Enum.at(topics, 2)),
         {:ok, creator} <- parse_topic_address(Enum.at(topics, 3)),
         {:ok, manifest_hash} <- parse_word_hex(data_hex, 2),
         {:ok, kind} <- parse_word_uint8(data_hex, 3) do
      {:ok,
       %{
         node_id: node_id,
         parent_id: parent_id,
         creator: creator,
         manifest_hash: manifest_hash,
         kind: kind
       }}
    end
  end

  @spec decode_node_created_topics(map()) :: {:ok, [String.t()]} | {:error, term()}
  defp decode_node_created_topics(log) do
    case map_fetch(log, "topics") do
      [topic0, node_id, parent_id, creator]
      when is_binary(topic0) and is_binary(node_id) and is_binary(parent_id) and
             is_binary(creator) ->
        if String.downcase(topic0) == @node_created_topic0 do
          {:ok, [topic0, node_id, parent_id, creator]}
        else
          {:error, :invalid_node_created_log_topics}
        end

      _ ->
        {:error, :invalid_node_created_log_topics}
    end
  end

  @spec decode_node_created_data(map()) :: {:ok, String.t()} | {:error, term()}
  defp decode_node_created_data(log) do
    case map_fetch(log, "data") do
      "0x" <> data_hex = full_data_hex ->
        if String.match?(full_data_hex, ~r/^0x[0-9a-fA-F]+$/) and byte_size(data_hex) >= 256 do
          {:ok, String.downcase(data_hex)}
        else
          {:error, :invalid_node_created_log_data}
        end

      _ ->
        {:error, :invalid_node_created_log_data}
    end
  end

  @spec parse_topic_uint(term()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp parse_topic_uint(topic) do
    case validate_hex_word(topic, :invalid_node_created_log_topics) do
      :ok -> parse_hex_quantity(topic)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec parse_topic_address(term()) :: {:ok, String.t()} | {:error, term()}
  defp parse_topic_address(topic) when is_binary(topic) do
    with :ok <- validate_hex_word(topic, :invalid_node_created_log_topics),
         "0x" <> topic_body <- String.downcase(topic),
         <<padding::binary-size(24), address_body::binary-size(40)>> <- topic_body,
         true <- String.match?(padding, ~r/^0+$/),
         {:ok, creator} <- normalize_address("0x" <> address_body) do
      {:ok, creator}
    else
      _ -> {:error, :invalid_node_created_log_topics}
    end
  end

  defp parse_topic_address(_topic), do: {:error, :invalid_node_created_log_topics}

  @spec parse_word_hex(String.t(), non_neg_integer()) :: {:ok, String.t()} | {:error, term()}
  defp parse_word_hex(data_hex, word_index) do
    with {:ok, word_hex} <- extract_word(data_hex, word_index),
         true <- String.match?(word_hex, @hex32_regex) do
      {:ok, "0x" <> String.downcase(word_hex)}
    else
      _ -> {:error, :invalid_node_created_log_data}
    end
  end

  @spec parse_word_uint8(String.t(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp parse_word_uint8(data_hex, word_index) do
    with {:ok, word_hex} <- extract_word(data_hex, word_index),
         {:ok, kind} <- parse_hex_quantity("0x" <> word_hex),
         {:ok, kind} <- normalize_uint8(kind) do
      {:ok, kind}
    else
      _ -> {:error, :invalid_node_created_log_data}
    end
  end

  @spec extract_word(String.t(), non_neg_integer()) :: {:ok, String.t()} | {:error, term()}
  defp extract_word(data_hex, word_index)
       when is_binary(data_hex) and is_integer(word_index) and word_index >= 0 do
    start_offset = word_index * 64

    if byte_size(data_hex) >= start_offset + 64 do
      {:ok, binary_part(data_hex, start_offset, 64)}
    else
      {:error, :invalid_node_created_log_data}
    end
  end

  defp extract_word(_data_hex, _word_index), do: {:error, :invalid_node_created_log_data}

  @spec validate_hex_word(term(), term()) :: :ok | {:error, term()}
  defp validate_hex_word(value, error_reason) when is_binary(value) do
    if Regex.match?(@hex_word_with_prefix_regex, value) do
      :ok
    else
      {:error, error_reason}
    end
  end

  defp validate_hex_word(_value, error_reason), do: {:error, error_reason}

  @spec ensure_log_field_match(atom(), term(), term()) :: :ok | {:error, term()}
  defp ensure_log_field_match(_field, expected, expected), do: :ok

  defp ensure_log_field_match(field, expected, actual) do
    {:error, {:node_created_log_mismatch, field, expected, actual}}
  end

  @spec parse_log_address(map()) :: {:ok, String.t()} | {:error, term()}
  defp parse_log_address(log) when is_map(log) do
    case normalize_address_value(map_fetch(log, "address")) do
      nil -> {:error, :invalid_node_created_log_address}
      address -> {:ok, address}
    end
  end

  defp parse_log_address(_log), do: {:error, :invalid_node_created_log}

  @spec validate_tx_hash(String.t()) :: :ok | {:error, :invalid_tx_hash}
  defp validate_tx_hash(tx_hash) when is_binary(tx_hash) do
    if Regex.match?(@tx_hash_exact_regex, tx_hash), do: :ok, else: {:error, :invalid_tx_hash}
  end

  defp validate_tx_hash(_tx_hash), do: {:error, :invalid_tx_hash}

  @spec topic0(map()) :: String.t() | nil
  defp topic0(log) when is_map(log) do
    case map_fetch(log, "topics") do
      [head | _tail] when is_binary(head) -> String.downcase(head)
      _ -> nil
    end
  end

  @spec map_fetch(map(), String.t()) :: term()
  defp map_fetch(map, key) when is_map(map) do
    atom_key =
      case key do
        "blockNumber" -> :blockNumber
        "logs" -> :logs
        "logIndex" -> :logIndex
        "status" -> :status
        "removed" -> :removed
        "address" -> :address
        "topics" -> :topics
        "data" -> :data
        _ -> nil
      end

    if atom_key, do: Map.get(map, key, Map.get(map, atom_key)), else: Map.get(map, key)
  end

  @spec normalize_node_created_verification(node_created_verification() | nil) ::
          {:ok, node_created_verification() | nil} | {:error, term()}
  defp normalize_node_created_verification(nil), do: {:ok, nil}

  defp normalize_node_created_verification(verification_input) when is_map(verification_input) do
    with {:ok, node_id_raw} <- fetch_verification_field(verification_input, :node_id),
         {:ok, parent_id_raw} <- fetch_verification_field(verification_input, :parent_id),
         {:ok, creator_raw} <- fetch_verification_field(verification_input, :creator),
         {:ok, manifest_hash_raw} <- fetch_verification_field(verification_input, :manifest_hash),
         {:ok, kind_raw} <- fetch_verification_field(verification_input, :kind),
         {:ok, node_id} <- normalize_uint(node_id_raw, :node_id),
         {:ok, parent_id} <- normalize_uint(parent_id_raw, :parent_id),
         {:ok, creator} <- normalize_address(creator_raw),
         {:ok, manifest_hash} <- normalize_manifest_hash(manifest_hash_raw),
         {:ok, kind} <- normalize_uint8(kind_raw) do
      {:ok,
       %{
         node_id: node_id,
         parent_id: parent_id,
         creator: creator,
         manifest_hash: manifest_hash,
         kind: kind
       }}
    else
      {:error, reason} ->
        {:error, {:invalid_node_created_verification, reason}}
    end
  end

  defp normalize_node_created_verification(_verification_input),
    do: {:error, {:invalid_node_created_verification, :not_map}}

  @spec fetch_verification_field(map(), atom()) :: {:ok, term()} | {:error, term()}
  defp fetch_verification_field(verification, key) do
    case Map.fetch(verification, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        case Map.fetch(verification, Atom.to_string(key)) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, {:missing_param, key}}
        end
    end
  end

  @spec stub_tx_hash() :: String.t()
  defp stub_tx_hash, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

  @spec config() :: map()
  defp config do
    raw_cfg = Application.get_env(:tech_tree, :ethereum, [])

    cfg_map =
      cond do
        Keyword.keyword?(raw_cfg) -> Map.new(raw_cfg)
        is_map(raw_cfg) -> raw_cfg
        true -> %{}
      end

    rpc_url = cfg_fetch(cfg_map, :rpc_url)
    registry_address = normalize_address_value(cfg_fetch(cfg_map, :registry_address))
    writer_private_key = cfg_fetch(cfg_map, :writer_private_key)
    requested_mode = parse_mode(cfg_fetch(cfg_map, :mode) || "auto")
    rpc_transport_ready? = non_empty_binary?(rpc_url) and non_empty_binary?(registry_address)

    %{
      mode: resolve_mode(requested_mode, rpc_transport_ready?),
      rpc_url: rpc_url,
      registry_address: registry_address,
      writer_private_key: writer_private_key,
      chain_id: normalize_chain_id(cfg_fetch(cfg_map, :chain_id)),
      cast_bin: cfg_fetch(cfg_map, :cast_bin) || "cast",
      cast_runner: cfg_fetch(cfg_map, :cast_runner),
      rpc_client: cfg_fetch(cfg_map, :rpc_client),
      req_options: cfg_fetch(cfg_map, :req_options)
    }
  end

  @spec cfg_fetch(map(), atom()) :: term()
  defp cfg_fetch(cfg, key) when is_map(cfg),
    do: Map.get(cfg, key, Map.get(cfg, Atom.to_string(key)))

  @spec non_empty_binary?(term()) :: boolean()
  defp non_empty_binary?(value) when is_binary(value), do: String.trim(value) != ""
  defp non_empty_binary?(_value), do: false

  @spec normalize_chain_id(term()) :: non_neg_integer() | nil
  defp normalize_chain_id(value) when is_integer(value) and value > 0, do: value

  defp normalize_chain_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp normalize_chain_id(_value), do: nil

  @spec parse_mode(term()) :: :auto | :stub | :rpc
  defp parse_mode(:stub), do: :stub
  defp parse_mode(:rpc), do: :rpc
  defp parse_mode(:auto), do: :auto
  defp parse_mode("stub"), do: :stub
  defp parse_mode("rpc"), do: :rpc
  defp parse_mode(_), do: :auto

  @spec resolve_mode(:auto | :stub | :rpc, boolean()) :: :stub | :rpc
  defp resolve_mode(:stub, _ready?), do: :stub
  defp resolve_mode(:rpc, _ready?), do: :rpc
  defp resolve_mode(:auto, true), do: :rpc
  defp resolve_mode(:auto, false), do: :stub

  @spec ensure_rpc_create_node_config(map()) :: :ok | {:error, term()}
  defp ensure_rpc_create_node_config(cfg) do
    with :ok <- ensure_rpc_receipt_config(cfg) do
      ensure_non_empty_config(cfg.writer_private_key, :writer_private_key)
    end
  end

  @spec ensure_rpc_receipt_config(map()) :: :ok | {:error, term()}
  defp ensure_rpc_receipt_config(cfg) do
    with :ok <- ensure_non_empty_config(cfg.rpc_url, :rpc_url) do
      ensure_non_empty_config(cfg.registry_address, :registry_address)
    end
  end

  @spec ensure_non_empty_config(term(), atom()) :: :ok | {:error, term()}
  defp ensure_non_empty_config(value, key) do
    if non_empty_binary?(value), do: :ok, else: {:error, {:rpc_config_missing, key}}
  end

  @spec ensure_chain_id_match(non_neg_integer() | nil, non_neg_integer()) ::
          :ok | {:error, term()}
  defp ensure_chain_id_match(nil, _resolved_chain_id), do: :ok

  defp ensure_chain_id_match(configured_chain_id, resolved_chain_id)
       when configured_chain_id == resolved_chain_id,
       do: :ok

  defp ensure_chain_id_match(configured_chain_id, resolved_chain_id) do
    {:error, {:chain_id_mismatch, configured: configured_chain_id, resolved: resolved_chain_id}}
  end
end
