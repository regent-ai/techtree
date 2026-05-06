defmodule TechTree.Ethereum do
  @moduledoc false

  alias TechTree.V1.Chain

  @required_publish_node_keys [
    :node_id,
    :subject_id,
    :aux_id,
    :author,
    :payload_hash,
    :node_type,
    :schema_version,
    :flags,
    :manifest_cid,
    :payload_cid
  ]

  @type publish_node_params :: %{
          required(:node_id) => non_neg_integer() | String.t(),
          required(:subject_id) => non_neg_integer() | String.t(),
          required(:aux_id) => non_neg_integer() | String.t(),
          required(:author) => String.t(),
          required(:payload_hash) => String.t(),
          required(:node_type) => 1 | 2 | 3,
          required(:schema_version) => 1,
          required(:flags) => non_neg_integer(),
          required(:manifest_cid) => String.t(),
          required(:payload_cid) => String.t()
        }

  @type receipt :: %{
          block_number: non_neg_integer(),
          chain_id: non_neg_integer(),
          contract_address: String.t(),
          log_index: non_neg_integer()
        }

  @default_chain_id 8_453
  @default_contract_address "0x0000000000000000000000000000000000000000"
  @publish_node_signature "publishNode((bytes32,bytes32,bytes32,bytes32,uint8,uint16,uint32,address),bytes,bytes)"
  @tx_hash_exact_regex ~r/^0x[0-9a-fA-F]{64}$/
  @tx_hash_in_text_regex ~r/0x[0-9a-fA-F]{64}/
  @address_regex ~r/^0x[0-9a-fA-F]{40}$/
  @hex32_regex ~r/^[0-9a-fA-F]{64}$/
  @private_key_regex ~r/^(0x)?[0-9a-fA-F]{64}$/

  @spec publish_node(publish_node_params()) :: {:ok, String.t()} | {:error, term()}
  def publish_node(params) when is_map(params) do
    with {:ok, normalized} <- normalize_publish_node_params(params) do
      case config().mode do
        :stub ->
          {:ok, stub_tx_hash()}

        :rpc ->
          publish_node_rpc(normalized)
      end
    end
  end

  def publish_node(_params), do: {:error, :invalid_params}

  @spec fetch_receipt(String.t(), map() | nil) :: {:ok, receipt()} | :not_found | {:error, term()}
  def fetch_receipt(tx_hash, verification_input) do
    cfg = config()

    case cfg.mode do
      :stub ->
        fetch_receipt_stub(tx_hash, cfg)

      :rpc ->
        fetch_receipt_rpc(tx_hash, cfg, verification_input)
    end
  end

  @spec publish_node_rpc(map()) :: {:ok, String.t()} | {:error, term()}
  defp publish_node_rpc(params) do
    cfg = config()

    with :ok <- ensure_rpc_publish_node_config(cfg),
         {:ok, writer_private_key} <- normalize_private_key(cfg.writer_private_key),
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
               @publish_node_signature,
               node_header_tuple(params),
               encode_bytes_arg(params.manifest_cid),
               encode_bytes_arg(params.payload_cid)
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

  @spec fetch_receipt_rpc(String.t(), map(), map() | nil) ::
          {:ok, receipt()} | :not_found | {:error, term()}
  defp fetch_receipt_rpc(tx_hash, cfg, verification_input) do
    with :ok <- ensure_rpc_receipt_config(cfg),
         :ok <- validate_tx_hash(tx_hash),
         {:ok, submission} <-
           verification_input
           |> normalize_receipt_verification(tx_hash)
           |> Chain.fetch_published_submission() do
      {:ok,
       %{
         block_number: submission.block_number,
         chain_id: submission.chain_id,
         contract_address: submission.contract_address,
         log_index: submission.log_index
       }}
    else
      :not_found -> :not_found
      {:error, reason} -> {:error, reason}
    end
  end

  @spec normalize_receipt_verification(map() | nil, String.t()) :: map()
  defp normalize_receipt_verification(nil, tx_hash), do: %{"tx_hash" => String.downcase(tx_hash)}

  defp normalize_receipt_verification(verification, tx_hash) when is_map(verification),
    do: Map.put(verification, "tx_hash", String.downcase(tx_hash))

  defp normalize_receipt_verification(_verification, tx_hash),
    do: %{"tx_hash" => String.downcase(tx_hash)}

  @spec normalize_publish_node_params(map()) :: {:ok, map()} | {:error, term()}
  defp normalize_publish_node_params(params) do
    with :ok <- ensure_required_publish_keys(params),
         {:ok, node_id} <- normalize_bytes32(Map.fetch!(params, :node_id), :node_id),
         {:ok, subject_id} <- normalize_bytes32(Map.fetch!(params, :subject_id), :subject_id),
         {:ok, aux_id} <- normalize_bytes32(Map.fetch!(params, :aux_id), :aux_id),
         {:ok, payload_hash} <- normalize_payload_hash(Map.fetch!(params, :payload_hash)),
         {:ok, node_type} <- normalize_uint(Map.fetch!(params, :node_type), :node_type, 1, 3),
         {:ok, schema_version} <-
           normalize_uint(Map.fetch!(params, :schema_version), :schema_version, 1, 65_535),
         {:ok, flags} <- normalize_uint(Map.fetch!(params, :flags), :flags, 0, 4_294_967_295),
         {:ok, author} <- normalize_address(Map.fetch!(params, :author)),
         {:ok, manifest_cid} <-
           normalize_non_empty_string(Map.fetch!(params, :manifest_cid), :manifest_cid),
         {:ok, payload_cid} <-
           normalize_non_empty_string(Map.fetch!(params, :payload_cid), :payload_cid) do
      {:ok,
       %{
         node_id: node_id,
         subject_id: subject_id,
         aux_id: aux_id,
         payload_hash: payload_hash,
         node_type: node_type,
         schema_version: schema_version,
         flags: flags,
         author: author,
         manifest_cid: manifest_cid,
         payload_cid: payload_cid
       }}
    end
  end

  @spec ensure_required_publish_keys(map()) :: :ok | {:error, term()}
  defp ensure_required_publish_keys(params) do
    Enum.reduce_while(@required_publish_node_keys, :ok, fn key, _acc ->
      if Map.has_key?(params, key) do
        {:cont, :ok}
      else
        {:halt, {:error, {:missing_param, key}}}
      end
    end)
  end

  @spec node_header_tuple(map()) :: String.t()
  defp node_header_tuple(params) do
    [
      params.node_id,
      params.subject_id,
      params.aux_id,
      params.payload_hash,
      Integer.to_string(params.node_type),
      Integer.to_string(params.schema_version),
      Integer.to_string(params.flags),
      params.author
    ]
    |> Enum.join(",")
    |> then(&"(#{&1})")
  end

  @spec encode_bytes_arg(String.t()) :: String.t()
  defp encode_bytes_arg(value), do: "0x" <> Base.encode16(value, case: :lower)

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

  @spec normalize_payload_hash(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp normalize_payload_hash("sha256:" <> value), do: normalize_hex32(value, :payload_hash)
  defp normalize_payload_hash("0x" <> value), do: normalize_hex32(value, :payload_hash)
  defp normalize_payload_hash("0X" <> value), do: normalize_hex32(value, :payload_hash)
  defp normalize_payload_hash(value), do: normalize_hex32(value, :payload_hash)

  @spec normalize_hex32(term(), atom()) :: {:ok, String.t()} | {:error, term()}
  defp normalize_hex32(value, field) when is_binary(value) do
    normalized = String.trim(value)

    if Regex.match?(@hex32_regex, normalized) do
      {:ok, "0x" <> String.downcase(normalized)}
    else
      {:error, {:invalid_param, field}}
    end
  end

  defp normalize_hex32(_value, field), do: {:error, {:invalid_param, field}}

  @spec normalize_bytes32(term(), atom()) :: {:ok, String.t()} | {:error, term()}
  defp normalize_bytes32(value, _field) when is_integer(value) and value >= 0 do
    {:ok, "0x" <> String.pad_leading(Integer.to_string(value, 16), 64, "0")}
  end

  defp normalize_bytes32("0x" <> value, field), do: normalize_hex32(value, field)
  defp normalize_bytes32("0X" <> value, field), do: normalize_hex32(value, field)
  defp normalize_bytes32(value, field), do: normalize_hex32(value, field)

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
      {:error, {:invalid_param, :author}}
    end
  end

  defp normalize_address(_), do: {:error, {:invalid_param, :author}}

  @spec normalize_address_value(term()) :: String.t() | nil
  defp normalize_address_value(address) when is_binary(address) do
    normalized = String.downcase(String.trim(address))
    if Regex.match?(@address_regex, normalized), do: normalized, else: nil
  end

  defp normalize_address_value(_), do: nil

  @spec normalize_uint(term(), atom(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp normalize_uint(value, _field, min, max)
       when is_integer(value) and value >= min and value <= max,
       do: {:ok, value}

  defp normalize_uint(_value, field, _min, _max), do: {:error, {:invalid_param, field}}

  @spec normalize_non_empty_string(term(), atom()) :: {:ok, String.t()} | {:error, term()}
  defp normalize_non_empty_string(value, field) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: {:error, {:invalid_param, field}}, else: {:ok, trimmed}
  end

  defp normalize_non_empty_string(_value, field), do: {:error, {:invalid_param, field}}

  @spec validate_tx_hash(String.t()) :: :ok | {:error, :invalid_tx_hash}
  defp validate_tx_hash(tx_hash) when is_binary(tx_hash) do
    if Regex.match?(@tx_hash_exact_regex, tx_hash), do: :ok, else: {:error, :invalid_tx_hash}
  end

  defp validate_tx_hash(_tx_hash), do: {:error, :invalid_tx_hash}

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
      cast_runner: cfg_fetch(cfg_map, :cast_runner)
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

  @spec ensure_rpc_publish_node_config(map()) :: :ok | {:error, term()}
  defp ensure_rpc_publish_node_config(cfg) do
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
end
