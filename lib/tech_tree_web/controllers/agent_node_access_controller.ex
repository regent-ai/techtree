defmodule TechTreeWeb.AgentNodeAccessController do
  @moduledoc false
  use TechTreeWeb, :controller

  alias TechTree.NodeAccess
  alias TechTreeWeb.{AgentApiResult, ApiError, ControllerHelpers}

  def payload(conn, %{"id" => id}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, node_id} <- ControllerHelpers.parse_positive_int(id),
         {:ok, payload} <- NodeAccess.fetch_payload_for_agent(node_id, agent) do
      json(conn, %{data: payload})
    else
      {:error, :invalid} ->
        ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_node_id"})

      {:error, :paid_payload_not_found} ->
        ApiError.render(conn, :not_found, %{"code" => "paid_payload_not_found"})

      {:error, :paid_payload_not_active} ->
        ApiError.render(conn, :unprocessable_entity, %{"code" => "paid_payload_not_active"})

      {:error, :payment_required} ->
        ApiError.render(conn, 402, %{"code" => "paid_payload_payment_required"})

      {:error, reason} ->
        AgentApiResult.render_reason(
          conn,
          :unprocessable_entity,
          "paid_payload_fetch_failed",
          reason
        )
    end
  end

  def purchase(conn, %{"id" => id, "tx_hash" => tx_hash}) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    with {:ok, node_id} <- ControllerHelpers.parse_positive_int(id),
         {:ok, %{payload: payload, entitlement: entitlement}} <-
           NodeAccess.verify_purchase_for_agent(node_id, agent, tx_hash) do
      conn
      |> put_status(:created)
      |> json(%{
        data: %{
          node_id: node_id,
          tx_hash: entitlement.tx_hash,
          chain_id: entitlement.chain_id,
          amount_usdc: entitlement.amount_usdc,
          listing_ref: payload.listing_ref,
          bundle_ref: payload.bundle_ref
        }
      })
    else
      {:error, :invalid} ->
        ApiError.render(conn, :unprocessable_entity, %{"code" => "invalid_node_id"})

      {:error, :duplicate_purchase_tx} ->
        ApiError.render(conn, :unprocessable_entity, %{"code" => "duplicate_purchase_tx"})

      {:error, :paid_payload_not_found} ->
        ApiError.render(conn, :not_found, %{"code" => "paid_payload_not_found"})

      {:error, :paid_payload_not_active} ->
        ApiError.render(conn, :unprocessable_entity, %{"code" => "paid_payload_not_active"})

      {:error, reason} ->
        AgentApiResult.render_reason(
          conn,
          :unprocessable_entity,
          "purchase_verification_failed",
          reason
        )
    end
  end
end
