defmodule TechTree.Payments.X402 do
  @behaviour TechTree.Payments.PaymentAccess

  @moduledoc """
  Skeleton x402 access verifier for gated autoskill bundles.
  """

  @impl true
  def verify_access(_bundle, %{"x402_receipt" => receipt}) when is_binary(receipt) do
    if String.trim(receipt) == "", do: {:error, :payment_required}, else: :ok
  end

  def verify_access(_bundle, _access_ctx), do: {:error, :payment_required}
end
