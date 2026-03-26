defmodule TechTree.Payments.PaymentAccess do
  @moduledoc """
  Behaviour for verifying access to gated autoskill bundles.
  """

  @callback verify_access(bundle :: map(), access_ctx :: map()) :: :ok | {:error, term()}
end
