defmodule TechTree.NodeAccess do
  @moduledoc false

  import Ecto.Query

  alias Decimal, as: D
  alias TechTree.Agents.AgentIdentity
  alias TechTree.Autoskill.Listing
  alias TechTree.Autoskill.NodeBundle
  alias TechTree.IPFS.LighthouseClient
  alias TechTree.NodeAccess.{NodePaidPayload, NodePurchaseEntitlement}
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  @purchase_settled_topic0 "0x55b709eb67e99747eb5949bc3721704e5db6bbc87add708787955b5741bd95fa"

  @address_regex ~r/^0x[0-9a-f]{40}$/
  @tx_hash_regex ~r/^0x[0-9a-f]{64}$/
  @hex_word_regex ~r/^0x[0-9a-f]{64}$/
  @micro_usdc D.new("1000000")

  def attach_projection(nodes, viewer \\ %{})

  def attach_projection(%Node{} = node, viewer) do
    case attach_projection([node], viewer) do
      [projected] -> projected
      _ -> node
    end
  end

  def attach_projection(nodes, viewer) when is_list(nodes) do
    node_ids =
      nodes
      |> Enum.map(& &1.id)
      |> Enum.reject(&is_nil/1)

    payloads_by_node_id =
      NodePaidPayload
      |> where([payload], payload.node_id in ^node_ids)
      |> Repo.all()
      |> Map.new(&{&1.node_id, &1})

    counts_by_node_id =
      NodePurchaseEntitlement
      |> where([entitlement], entitlement.node_id in ^node_ids)
      |> group_by([entitlement], entitlement.node_id)
      |> select([entitlement], {entitlement.node_id, count(entitlement.id)})
      |> Repo.all()
      |> Map.new()

    viewer_wallet = normalize_wallet(viewer[:wallet_address] || viewer["wallet_address"])

    entitled_node_ids =
      case viewer_wallet do
        nil ->
          MapSet.new()

        wallet ->
          NodePurchaseEntitlement
          |> where(
            [entitlement],
            entitlement.node_id in ^node_ids and entitlement.buyer_wallet_address == ^wallet
          )
          |> select([entitlement], entitlement.node_id)
          |> Repo.all()
          |> MapSet.new()
      end

    Enum.map(nodes, fn node ->
      case Map.get(payloads_by_node_id, node.id) do
        nil ->
          %{node | paid_payload: nil}

        payload ->
          %{node | paid_payload: project_payload(payload, counts_by_node_id, entitled_node_ids)}
      end
    end)
  end

  def create_paid_payload(%Node{} = node, %AgentIdentity{} = seller_agent, attrs)
      when is_map(attrs) do
    payload_attrs =
      attrs
      |> normalize_optional_payload_attrs()
      |> Map.put("node_id", node.id)
      |> Map.put("seller_agent_id", seller_agent.id)
      |> ensure_refs(node)

    %NodePaidPayload{}
    |> NodePaidPayload.changeset(payload_attrs)
    |> Repo.insert()
  end

  def upsert_paid_payload(%Node{} = node, %AgentIdentity{} = seller_agent, attrs)
      when is_map(attrs) do
    payload = Repo.get_by(NodePaidPayload, node_id: node.id) || %NodePaidPayload{}

    payload_attrs =
      attrs
      |> normalize_optional_payload_attrs()
      |> Map.put("node_id", node.id)
      |> Map.put("seller_agent_id", seller_agent.id)
      |> ensure_refs(node)

    payload
    |> NodePaidPayload.changeset(payload_attrs)
    |> Repo.insert_or_update()
  end

  def sync_autoskill_bundle(
        %Node{} = node,
        %AgentIdentity{} = seller_agent,
        %NodeBundle{} = bundle
      ) do
    if bundle.access_mode == :gated_paid do
      upsert_paid_payload(node, seller_agent, %{
        "status" => "draft",
        "encrypted_payload_uri" => bundle.encrypted_bundle_uri,
        "encrypted_payload_cid" => bundle.encrypted_bundle_cid,
        "payload_hash" => bundle.bundle_hash,
        "encryption_meta" => bundle.encryption_meta || %{},
        "access_policy" => bundle.access_policy || %{}
      })
    else
      {:ok, nil}
    end
  end

  def activate_from_listing(%Listing{} = listing) do
    node = Repo.get!(Node, listing.skill_node_id)
    seller_agent = Repo.get!(AgentIdentity, listing.seller_agent_id)

    upsert_paid_payload(node, seller_agent, %{
      "status" => Atom.to_string(listing.status),
      "chain_id" => listing.chain_id,
      "settlement_contract_address" => listing_settlement_contract(listing),
      "usdc_token_address" => listing.usdc_token_address,
      "treasury_address" => listing.treasury_address,
      "seller_payout_address" => listing.seller_payout_address,
      "price_usdc" => decimal_to_string(listing.price_usdc),
      "access_policy" => listing.listing_meta || %{}
    })
  end

  def verify_purchase_for_agent(node_id, %AgentIdentity{} = agent, tx_hash) do
    verify_purchase(node_id, tx_hash, %{
      wallet_address: agent.wallet_address,
      buyer_agent_id: agent.id
    })
  end

  def verify_purchase(node_id, tx_hash, buyer_ctx \\ %{}) do
    with {:ok, payload, node} <- fetch_active_payload(node_id),
         {:ok, normalized_tx_hash} <- normalize_tx_hash(tx_hash),
         {:ok, buyer_wallet} <- buyer_wallet_from_context(buyer_ctx),
         {:ok, verified} <- verify_settlement_tx(payload, normalized_tx_hash, buyer_wallet),
         attrs <- entitlement_attrs(node, payload, verified, buyer_ctx),
         {:ok, entitlement} <- persist_entitlement(attrs) do
      {:ok, %{payload: payload, entitlement: entitlement}}
    end
  end

  def fetch_payload_for_agent(node_id, %AgentIdentity{} = agent) do
    with {:ok, payload, _node} <- fetch_active_payload(node_id),
         :ok <- authorize_payload_access(payload, agent.wallet_address, agent.id) do
      {:ok, encode_payload_download(payload)}
    end
  end

  def seller_summary_for_wallet(wallet_address) do
    wallet = normalize_wallet(wallet_address)

    seller_agent_ids =
      AgentIdentity
      |> where([agent], agent.wallet_address == ^wallet)
      |> select([agent], agent.id)
      |> Repo.all()

    summarize_sales(seller_agent_ids)
  end

  def seller_summary_for_agent(agent_id) when is_integer(agent_id) do
    summarize_sales([agent_id])
  end

  defp project_payload(payload, counts_by_node_id, entitled_node_ids) do
    %{
      status: Atom.to_string(payload.status),
      delivery_mode: Atom.to_string(payload.delivery_mode),
      payment_rail: Atom.to_string(payload.payment_rail),
      chain_id: payload.chain_id,
      settlement_contract_address: payload.settlement_contract_address,
      usdc_token_address: payload.usdc_token_address,
      treasury_address: payload.treasury_address,
      seller_payout_address: payload.seller_payout_address,
      price_usdc: decimal_to_string(payload.price_usdc),
      listing_ref: payload.listing_ref,
      bundle_ref: payload.bundle_ref,
      verified_purchase_count: Map.get(counts_by_node_id, payload.node_id, 0),
      viewer_has_verified_purchase: MapSet.member?(entitled_node_ids, payload.node_id)
    }
  end

  defp normalize_optional_payload_attrs(attrs) when is_map(attrs) do
    attrs
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> drop_nil_values()
  end

  defp ensure_refs(attrs, %Node{} = node) do
    attrs
    |> Map.put_new("listing_ref", stable_ref("listing:#{node.id}"))
    |> Map.put_new(
      "bundle_ref",
      stable_ref(
        "bundle:#{node.id}:#{Map.get(attrs, "payload_hash") || Map.get(attrs, "encrypted_payload_cid") || Map.get(attrs, "encrypted_payload_uri")}"
      )
    )
  end

  defp stable_ref(value) when is_binary(value) do
    "0x" <> Base.encode16(:crypto.hash(:sha256, value), case: :lower)
  end

  defp fetch_active_payload(node_id) do
    normalized_node_id =
      case node_id do
        value when is_integer(value) and value > 0 ->
          {:ok, value}

        value when is_binary(value) ->
          case Integer.parse(String.trim(value)) do
            {parsed, ""} when parsed > 0 -> {:ok, parsed}
            _ -> {:error, :invalid_node_id}
          end

        _ ->
          {:error, :invalid_node_id}
      end

    with {:ok, normalized_node_id} <- normalized_node_id,
         %Node{} = node <- Repo.get(Node, normalized_node_id) || {:error, :node_not_found},
         %NodePaidPayload{} = payload <-
           Repo.get_by(NodePaidPayload, node_id: normalized_node_id) ||
             {:error, :paid_payload_not_found},
         true <- payload.status == :active || {:error, :paid_payload_not_active} do
      {:ok, payload, node}
    end
  end

  defp buyer_wallet_from_context(ctx) when is_map(ctx) do
    case normalize_wallet(ctx[:wallet_address] || ctx["wallet_address"]) do
      nil -> {:error, :buyer_wallet_required}
      wallet -> {:ok, wallet}
    end
  end

  defp verify_settlement_tx(%NodePaidPayload{} = payload, tx_hash, buyer_wallet) do
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

  defp entitlement_attrs(node, payload, verified, buyer_ctx) do
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

  defp persist_entitlement(attrs) do
    %NodePurchaseEntitlement{}
    |> NodePurchaseEntitlement.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, entitlement} ->
        {:ok, entitlement}

      {:error, %Ecto.Changeset{} = changeset} ->
        if Enum.any?(changeset.errors, fn
             {:tx_hash, {_message, opts}} -> opts[:constraint] == :unique
             _ -> false
           end) do
          {:error, :duplicate_purchase_tx}
        else
          {:error, changeset}
        end
    end
  rescue
    Ecto.ConstraintError -> {:error, :duplicate_purchase_tx}
  end

  defp authorize_payload_access(payload, wallet_address, buyer_agent_id) do
    normalized_wallet = normalize_wallet(wallet_address)

    cond do
      payload.seller_agent_id == buyer_agent_id ->
        :ok

      Repo.exists?(
        from entitlement in NodePurchaseEntitlement,
          where:
            entitlement.node_id == ^payload.node_id and
                entitlement.buyer_wallet_address == ^normalized_wallet
      ) ->
        :ok

      true ->
        {:error, :payment_required}
    end
  end

  defp encode_payload_download(%NodePaidPayload{} = payload) do
    %{
      node_id: payload.node_id,
      encrypted_payload_uri: payload.encrypted_payload_uri,
      download_url:
        case payload.encrypted_payload_cid do
          cid when is_binary(cid) and cid != "" -> LighthouseClient.gateway_url(cid)
          _ -> nil
        end,
      encryption_meta: payload.encryption_meta || %{},
      access_policy: payload.access_policy || %{}
    }
  end

  defp summarize_sales([]) do
    %{verified_purchase_count: 0, total_sales_usdc: "0"}
  end

  defp summarize_sales(seller_agent_ids) do
    [summary] =
      NodePurchaseEntitlement
      |> where([entitlement], entitlement.seller_agent_id in ^seller_agent_ids)
      |> select([entitlement], %{
        verified_purchase_count: count(entitlement.id),
        total_sales_usdc: coalesce(sum(entitlement.amount_usdc), 0)
      })
      |> Repo.all()
      |> case do
        [] -> [%{verified_purchase_count: 0, total_sales_usdc: D.new("0")}]
        rows -> rows
      end

    %{
      verified_purchase_count: summary.verified_purchase_count,
      total_sales_usdc: decimal_to_string(summary.total_sales_usdc)
    }
  end

  defp receipt_from_rpc(rpc_url, tx_hash) do
    rpc_request(rpc_url, "eth_getTransactionReceipt", [tx_hash])
  end

  defp chain_id_from_rpc(rpc_url) do
    with {:ok, "0x" <> hex} <- rpc_request(rpc_url, "eth_chainId", []) do
      case Integer.parse(hex, 16) do
        {chain_id, ""} -> {:ok, chain_id}
        _ -> {:error, :invalid_chain_id}
      end
    end
  end

  defp rpc_request(rpc_url, method, params) do
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

  defp verify_receipt_status(%{"status" => "0x1"}), do: :ok
  defp verify_receipt_status(%{"status" => 1}), do: :ok
  defp verify_receipt_status(_receipt), do: {:error, :purchase_tx_failed}

  defp find_purchase_event(%{"logs" => logs}, %NodePaidPayload{} = payload) when is_list(logs) do
    normalized_contract = normalize_wallet(payload.settlement_contract_address)

    logs
    |> Enum.find(fn log ->
      is_map(log) and normalize_wallet(log["address"]) == normalized_contract and
        List.first(log["topics"] || []) == @purchase_settled_topic0
    end)
    |> case do
      nil -> {:error, :purchase_event_not_found}
      log -> decode_purchase_event(log)
    end
  end

  defp find_purchase_event(_receipt, _payload), do: {:error, :purchase_event_not_found}

  defp decode_purchase_event(%{
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

  defp decode_purchase_event(_log), do: {:error, :purchase_event_invalid}

  defp decode_purchase_data("0x" <> hex) when rem(byte_size(hex), 64) == 0 do
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

  defp decode_purchase_data(_data), do: {:error, :purchase_event_invalid}

  defp verify_event(event, %NodePaidPayload{} = payload, buyer_wallet) do
    expected_amount = decimal_to_micro_units(payload.price_usdc)

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

  defp decode_topic_address(topic) when is_binary(topic) do
    normalized = String.downcase(topic)

    if Regex.match?(@hex_word_regex, normalized) do
      {:ok, "0x" <> String.slice(normalized, -40, 40)}
    else
      {:error, :invalid_topic_address}
    end
  end

  defp hex_to_integer(hex) when is_binary(hex) do
    case Integer.parse(hex, 16) do
      {value, ""} -> {:ok, value}
      _ -> {:error, :invalid_hex_value}
    end
  end

  defp normalize_tx_hash(tx_hash) when is_binary(tx_hash) do
    normalized = String.downcase(String.trim(tx_hash))

    if Regex.match?(@tx_hash_regex, normalized),
      do: {:ok, normalized},
      else: {:error, :invalid_tx_hash}
  end

  defp normalize_tx_hash(_tx_hash), do: {:error, :invalid_tx_hash}

  defp normalize_wallet(wallet) when is_binary(wallet) do
    normalized = String.downcase(String.trim(wallet))
    if Regex.match?(@address_regex, normalized), do: normalized, else: nil
  end

  defp normalize_wallet(_wallet), do: nil

  defp rpc_url_for_chain(chain_id) when is_integer(chain_id) do
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

  defp rpc_url_for_chain(_chain_id), do: {:error, :purchase_rpc_not_configured}

  defp listing_settlement_contract(%Listing{chain_id: chain_id}) do
    config = Application.get_env(:tech_tree, :autoskill, [])

    case Keyword.get(config, :chains, %{}) do
      %{^chain_id => value} ->
        Map.get(
          value,
          :settlement_contract_address,
          Map.get(value, "settlement_contract_address")
        )

      chain_map when is_map(chain_map) ->
        case Map.get(chain_map, chain_id) || Map.get(chain_map, Integer.to_string(chain_id)) do
          nil ->
            nil

          value ->
            Map.get(
              value,
              :settlement_contract_address,
              Map.get(value, "settlement_contract_address")
            )
        end

      _ ->
        nil
    end
  end

  defp decimal_to_micro_units(nil), do: 0

  defp decimal_to_micro_units(value) do
    value
    |> D.new()
    |> D.mult(@micro_usdc)
    |> D.round(0)
    |> D.to_integer()
  end

  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(%D{} = value), do: D.to_string(value)
  defp decimal_to_string(value) when is_binary(value), do: value
  defp decimal_to_string(value), do: to_string(value)

  defp drop_nil_values(map) do
    Map.reject(map, fn
      {_key, nil} -> true
      {_key, value} when is_binary(value) -> String.trim(value) == ""
      _ -> false
    end)
  end
end
