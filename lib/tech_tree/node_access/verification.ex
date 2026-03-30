defmodule TechTree.NodeAccess.Verification do
  @moduledoc false

  alias TechTree.NodeAccess.NodePaidPayload
  alias TechTree.NodeAccess.Payloads
  alias TechTree.Nodes.Node

  @address_regex ~r/^0x[0-9a-f]{40}$/
  @tx_hash_regex ~r/^0x[0-9a-f]{64}$/
  @hex_word_regex ~r/^0x[0-9a-f]{64}$/

  # This is the public topic0 fingerprint for the PurchaseSettled(...) event log,
  # not a wallet secret or signing key.
  @purchase_settled_event_topic0 "0x55b709eb67e99747eb5949bc3721704e5db6bbc87add708787955b5741bd95fa"

  def buyer_wallet_from_context(ctx) when is_map(ctx) do
    case normalize_wallet(ctx[:wallet_address] || ctx["wallet_address"]) do
      nil -> {:error, :buyer_wallet_required}
      wallet -> {:ok, wallet}
    end
  end

  def verify_settlement_tx(%NodePaidPayload{} = payload, tx_hash, buyer_wallet) do
    with {:ok, rpc_url} <- rpc_url_for_chain(payload.chain_id),
         {:ok, chain_id} <- chain_id_from_rpc(rpc_url),
         true <- chain_id == payload.chain_id || {:error, :purchase_chain_mismatch},
         {:ok, receipt} <- receipt_from_rpc(rpc_url, tx_hash),
         :ok <- verify_receipt_status(receipt),
         {:ok, event} <- find_purchase_event(receipt, payload),
         :ok <- verify_event(event, payload, buyer_wallet) do
      {:ok,
       %{
         tx_hash: tx_hash,
         chain_id: chain_id,
         buyer_wallet_address: buyer_wallet,
         amount_usdc: payload.price_usdc,
         listing_ref: payload.listing_ref,
         bundle_ref: payload.bundle_ref
       }}
    end
  end

  def entitlement_attrs(%Node{} = node, %NodePaidPayload{} = payload, verified, buyer_ctx) do
    %{
      node_id: node.id,
      seller_agent_id: payload.seller_agent_id,
      buyer_agent_id: buyer_ctx[:buyer_agent_id] || buyer_ctx["buyer_agent_id"],
      buyer_human_id: buyer_ctx[:buyer_human_id] || buyer_ctx["buyer_human_id"],
      buyer_wallet_address: verified.buyer_wallet_address,
      tx_hash: verified.tx_hash,
      chain_id: verified.chain_id,
      amount_usdc: verified.amount_usdc,
      verification_status: :verified,
      listing_ref: verified.listing_ref,
      bundle_ref: verified.bundle_ref
    }
  end

  def normalize_tx_hash(tx_hash) when is_binary(tx_hash) do
    normalized = String.downcase(String.trim(tx_hash))

    if Regex.match?(@tx_hash_regex, normalized),
      do: {:ok, normalized},
      else: {:error, :invalid_tx_hash}
  end

  def normalize_tx_hash(_tx_hash), do: {:error, :invalid_tx_hash}

  def normalize_wallet(wallet) when is_binary(wallet) do
    normalized = String.downcase(String.trim(wallet))
    if Regex.match?(@address_regex, normalized), do: normalized, else: nil
  end

  def normalize_wallet(_wallet), do: nil

  def receipt_from_rpc(rpc_url, tx_hash) do
    rpc_request(rpc_url, "eth_getTransactionReceipt", [tx_hash])
  end

  def chain_id_from_rpc(rpc_url) do
    with {:ok, "0x" <> hex} <- rpc_request(rpc_url, "eth_chainId", []) do
      case Integer.parse(hex, 16) do
        {chain_id, ""} -> {:ok, chain_id}
        _ -> {:error, :invalid_chain_id}
      end
    end
  end

  def rpc_request(rpc_url, method, params) do
    payload = %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}

    case Application.get_env(:tech_tree, :autoskill, [])[:rpc_client] do
      rpc_client when is_function(rpc_client, 2) ->
        case rpc_client.(rpc_url, payload) do
          {:ok, %{"result" => result}} -> {:ok, result}
          {:ok, %{"error" => error}} -> {:error, {:rpc_error, 200, error}}
          {:ok, response} -> {:error, {:rpc_http_error, 200, response}}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        case Req.post(url: rpc_url, json: payload) do
          {:ok, %Req.Response{status: status, body: %{"result" => result}}}
          when status in 200..299 ->
            {:ok, result}

          {:ok, %Req.Response{status: status, body: %{"error" => error}}} ->
            {:error, {:rpc_error, status, error}}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, {:rpc_http_error, status, body}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def verify_receipt_status(%{"status" => "0x1"}), do: :ok
  def verify_receipt_status(%{"status" => 1}), do: :ok
  def verify_receipt_status(_receipt), do: {:error, :purchase_tx_failed}

  def find_purchase_event(%{"logs" => logs}, %NodePaidPayload{} = payload) when is_list(logs) do
    normalized_contract = normalize_wallet(payload.settlement_contract_address)

    logs
    |> Enum.find(fn log ->
      is_map(log) and normalize_wallet(log["address"]) == normalized_contract and
        List.first(log["topics"] || []) == @purchase_settled_event_topic0
    end)
    |> case do
      nil -> {:error, :purchase_event_not_found}
      log -> decode_purchase_event(log)
    end
  end

  def find_purchase_event(_receipt, _payload), do: {:error, :purchase_event_not_found}

  def decode_purchase_event(%{
        "topics" => [_, listing_ref, buyer_topic, seller_topic],
        "data" => data
      })
      when is_binary(listing_ref) and is_binary(buyer_topic) and is_binary(seller_topic) and
             is_binary(data) do
    with {:ok, bundle_ref, amount, _treasury_amount, _seller_amount} <- decode_purchase_data(data),
         {:ok, buyer_wallet} <- decode_topic_address(buyer_topic),
         {:ok, seller_wallet} <- decode_topic_address(seller_topic) do
      {:ok,
       %{
         listing_ref: String.downcase(listing_ref),
         buyer_wallet: buyer_wallet,
         seller_wallet: seller_wallet,
         bundle_ref: String.downcase(bundle_ref),
         amount_raw: amount
       }}
    end
  end

  def decode_purchase_event(_log), do: {:error, :purchase_event_invalid}

  def decode_purchase_data("0x" <> hex) when rem(byte_size(hex), 64) == 0 do
    case String.downcase(hex) do
      <<bundle_ref::binary-size(64), amount_hex::binary-size(64), treasury_hex::binary-size(64),
        seller_hex::binary-size(64), _rest::binary>> ->
        with {:ok, amount} <- hex_to_integer(amount_hex),
             {:ok, treasury_amount} <- hex_to_integer(treasury_hex),
             {:ok, seller_amount} <- hex_to_integer(seller_hex) do
          {:ok, "0x" <> bundle_ref, amount, treasury_amount, seller_amount}
        end

      _ ->
        {:error, :purchase_event_invalid}
    end
  end

  def decode_purchase_data(_data), do: {:error, :purchase_event_invalid}

  def verify_event(event, %NodePaidPayload{} = payload, buyer_wallet) do
    expected_amount = Payloads.decimal_to_micro_units(payload.price_usdc)

    cond do
      String.downcase(event.listing_ref) != String.downcase(payload.listing_ref) ->
        {:error, :purchase_listing_ref_mismatch}

      String.downcase(event.bundle_ref) != String.downcase(payload.bundle_ref) ->
        {:error, :purchase_bundle_ref_mismatch}

      event.buyer_wallet != buyer_wallet ->
        {:error, :purchase_buyer_mismatch}

      event.seller_wallet != normalize_wallet(payload.seller_payout_address) ->
        {:error, :purchase_seller_mismatch}

      event.amount_raw != expected_amount ->
        {:error, :purchase_amount_mismatch}

      true ->
        :ok
    end
  end

  def decode_topic_address(topic) when is_binary(topic) do
    normalized = String.downcase(topic)

    if Regex.match?(@hex_word_regex, normalized) do
      {:ok, "0x" <> String.slice(normalized, -40, 40)}
    else
      {:error, :invalid_topic_address}
    end
  end

  def decode_topic_address(_topic), do: {:error, :invalid_topic_address}

  def hex_to_integer(hex) when is_binary(hex) do
    case Integer.parse(hex, 16) do
      {value, ""} -> {:ok, value}
      _ -> {:error, :invalid_hex_value}
    end
  end

  def rpc_url_for_chain(chain_id) when is_integer(chain_id) do
    config = Application.get_env(:tech_tree, :autoskill, [])
    chains = Keyword.get(config, :chains, %{})
    chain_config = Map.get(chains, chain_id) || Map.get(chains, Integer.to_string(chain_id))

    rpc_url =
      case chain_config do
        %{rpc_url: value} -> value
        %{"rpc_url" => value} -> value
        _ -> nil
      end

    resolved =
      rpc_url ||
        case chain_id do
          84_532 ->
            System.get_env("BASE_SEPOLIA_RPC_URL") || System.get_env("ANVIL_RPC_URL")

          8_453 ->
            System.get_env("BASE_MAINNET_RPC_URL") || System.get_env("BASE_RPC_URL")

          1 ->
            System.get_env("ETHEREUM_MAINNET_RPC_URL") || System.get_env("ETHEREUM_RPC_URL")

          11_155_111 ->
            System.get_env("ETHEREUM_SEPOLIA_RPC_URL") || System.get_env("ANVIL_RPC_URL")

          _ ->
            nil
        end

    case resolved do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :purchase_rpc_not_configured}
    end
  end

  def rpc_url_for_chain(_chain_id), do: {:error, :purchase_rpc_not_configured}
end
