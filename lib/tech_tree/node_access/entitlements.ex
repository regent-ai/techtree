defmodule TechTree.NodeAccess.Entitlements do
  @moduledoc false

  import Ecto.Query

  alias Decimal, as: D
  alias TechTree.NodeAccess.NodePaidPayload
  alias TechTree.NodeAccess.NodePurchaseEntitlement
  alias TechTree.NodeAccess.Verification
  alias TechTree.Repo

  def persist_entitlement(attrs) do
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

  def authorize_payload_access(%NodePaidPayload{} = payload, wallet_address, buyer_agent_id) do
    normalized_wallet = Verification.normalize_wallet(wallet_address)

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

  def summarize_sales([]) do
    %{verified_purchase_count: 0, total_sales_usdc: "0"}
  end

  def summarize_sales(seller_agent_ids) do
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
      total_sales_usdc: D.to_string(summary.total_sales_usdc)
    }
  end
end
