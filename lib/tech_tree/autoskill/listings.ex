defmodule TechTree.Autoskill.Listings do
  @moduledoc false

  import Ecto.Changeset, only: [add_error: 3, get_field: 2]
  import Ecto.Query

  alias TechTree.Autoskill.{Listing, NodeBundle, Result, Review}
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  @listing_threshold 10

  def eligible_for_listing?(skill_node_id) do
    skill = Repo.get!(Node, normalize_id(skill_node_id))
    count = distinct_replicable_review_count(skill.id, skill.creator_agent_id)
    count >= @listing_threshold
  end

  def normalize_listing_attrs(attrs, skill_node_id, seller_agent_id) do
    {:ok,
     %{
       "skill_node_id" => skill_node_id,
       "seller_agent_id" => seller_agent_id,
       "payment_rail" => attrs["payment_rail"] || attrs[:payment_rail] || "onchain",
       "chain_id" => attrs["chain_id"] || attrs[:chain_id],
       "usdc_token_address" => attrs["usdc_token_address"] || attrs[:usdc_token_address],
       "treasury_address" => attrs["treasury_address"] || attrs[:treasury_address],
       "seller_payout_address" => attrs["seller_payout_address"] || attrs[:seller_payout_address],
       "price_usdc" => attrs["price_usdc"] || attrs[:price_usdc],
       "treasury_bps" => 100,
       "seller_bps" => 9900,
       "listing_meta" => attrs["listing_meta"] || attrs[:listing_meta] || %{}
     }}
  end

  def validate_listing_chain(%Ecto.Changeset{} = changeset) do
    case get_field(changeset, :chain_id) do
      chain_id when is_integer(chain_id) ->
        with {:ok, config} <- chain_config(chain_id),
             :ok <-
               ensure_matches_config(changeset, :usdc_token_address, config.usdc_token_address),
             :ok <- ensure_matches_config(changeset, :treasury_address, config.treasury_address) do
          changeset
        else
          {:error, reason} -> add_error(changeset, :chain_id, Atom.to_string(reason))
        end

      _ ->
        changeset
    end
  end

  def encode_listing(%Listing{} = listing) do
    settlement_contract_address =
      case chain_config(listing.chain_id) do
        {:ok, config} -> config.settlement_contract_address
        _ -> nil
      end

    %{
      id: listing.id,
      skill_node_id: listing.skill_node_id,
      seller_agent_id: listing.seller_agent_id,
      status: Atom.to_string(listing.status),
      payment_rail: Atom.to_string(listing.payment_rail),
      chain_id: listing.chain_id,
      settlement_contract_address: settlement_contract_address,
      usdc_token_address: listing.usdc_token_address,
      treasury_address: listing.treasury_address,
      seller_payout_address: listing.seller_payout_address,
      price_usdc: listing.price_usdc,
      treasury_bps: listing.treasury_bps,
      seller_bps: listing.seller_bps,
      listing_meta: listing.listing_meta || %{},
      inserted_at: listing.inserted_at,
      updated_at: listing.updated_at
    }
  end

  def fetch_node_kind(node_id, expected_kind) do
    case Repo.get(Node, normalize_id(node_id)) do
      %Node{kind: ^expected_kind} = node -> {:ok, node}
      %Node{} -> {:error, :autoskill_invalid_node_kind}
      nil -> {:error, :node_not_found}
    end
  end

  def ensure_bundle_type(node_id, expected_type) do
    case Repo.get_by(NodeBundle, node_id: normalize_id(node_id)) do
      %NodeBundle{bundle_type: ^expected_type} -> :ok
      %NodeBundle{} -> {:error, :autoskill_bundle_type_mismatch}
      nil -> {:error, :autoskill_bundle_not_found}
    end
  end

  def validate_review_result(attrs, skill_node_id) do
    case attrs["kind"] || attrs[:kind] do
      kind when kind in ["replicable", :replicable] ->
        result_id = attrs["result_id"] || attrs[:result_id]

        with {:ok, normalized_result_id} <- normalize_id_safe(result_id) do
          case Repo.get(Result, normalized_result_id) do
            %Result{skill_node_id: ^skill_node_id} -> :ok
            %Result{} -> {:error, :autoskill_result_skill_mismatch}
            nil -> {:error, :autoskill_result_not_found}
          end
        end

      _ ->
        :ok
    end
  end

  def chain_config(chain_id) do
    config = Application.get_env(:tech_tree, :autoskill, [])

    case Keyword.get(config, :chains, %{}) do
      %{^chain_id => chain_config} ->
        {:ok, normalize_chain_config(chain_config)}

      chain_map when is_map(chain_map) ->
        case Map.get(chain_map, chain_id) || Map.get(chain_map, Integer.to_string(chain_id)) do
          nil -> {:error, :autoskill_chain_unsupported}
          value -> {:ok, normalize_chain_config(value)}
        end

      _ ->
        {:error, :autoskill_chain_unsupported}
    end
  end

  def normalize_id(value) when is_integer(value), do: value
  def normalize_id(value) when is_binary(value), do: String.to_integer(String.trim(value))

  def normalize_id_safe(value) when is_integer(value) and value > 0, do: {:ok, value}

  def normalize_id_safe(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> {:error, :autoskill_result_not_found}
    end
  end

  def normalize_id_safe(_value), do: {:error, :autoskill_result_not_found}

  defp distinct_replicable_review_count(skill_node_id, creator_id) do
    Review
    |> where(
      [review],
      review.skill_node_id == ^skill_node_id and review.kind == :replicable and
        review.reviewer_agent_id != ^creator_id
    )
    |> select([review], count(fragment("distinct ?", review.reviewer_agent_id)))
    |> Repo.one()
  end

  defp ensure_matches_config(changeset, field, expected) do
    actual = get_field(changeset, field)

    cond do
      not is_binary(expected) or String.trim(expected) == "" ->
        {:error, :autoskill_chain_not_configured}

      is_binary(actual) and String.downcase(actual) == String.downcase(expected) ->
        :ok

      true ->
        {:error, :autoskill_chain_mismatch}
    end
  end

  defp normalize_chain_config(config) when is_list(config) do
    %{
      settlement_contract_address: Keyword.get(config, :settlement_contract_address),
      usdc_token_address: Keyword.get(config, :usdc_token_address),
      treasury_address: Keyword.get(config, :treasury_address)
    }
  end

  defp normalize_chain_config(config) when is_map(config) do
    %{
      settlement_contract_address:
        Map.get(
          config,
          :settlement_contract_address,
          Map.get(config, "settlement_contract_address")
        ),
      usdc_token_address:
        Map.get(config, :usdc_token_address, Map.get(config, "usdc_token_address")),
      treasury_address: Map.get(config, :treasury_address, Map.get(config, "treasury_address"))
    }
  end

  defp normalize_chain_config(_config) do
    %{
      settlement_contract_address: nil,
      usdc_token_address: nil,
      treasury_address: nil
    }
  end
end
