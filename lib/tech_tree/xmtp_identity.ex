defmodule TechTree.XmtpIdentity do
  @moduledoc false

  alias TechTree.Accounts
  alias TechTree.Accounts.HumanUser
  alias XmtpElixirSdk.{Client, Clients, Runtime, Types}
  alias XmtpElixirSdk.Error

  @runtime_name __MODULE__.Runtime

  @type ensure_result ::
          {:ready, HumanUser.t()}
          | {:signature_required, HumanUser.t(), map()}

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    Runtime.child_spec(Keyword.put_new(opts, :name, @runtime_name))
  end

  @spec ensure_identity(HumanUser.t()) :: {:ok, ensure_result()} | {:error, term()}
  def ensure_identity(%HumanUser{} = human) do
    case ready_inbox_id(human) do
      {:ok, _inbox_id} ->
        {:ok, {:ready, human}}

      {:error, :xmtp_identity_required} ->
        with {:ok, wallet_address} <- wallet_address(human) do
          create_signature_request(human, wallet_address)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec ready_inbox_id(HumanUser.t()) ::
          {:ok, String.t()} | {:error, :xmtp_identity_required | :wallet_address_required}
  def ready_inbox_id(%HumanUser{} = human) do
    with {:ok, wallet_address} <- wallet_address(human),
         stored_inbox_id when not is_nil(stored_inbox_id) <-
           normalized_inbox_id(human.xmtp_inbox_id),
         true <- stored_inbox_id == derived_inbox_id(wallet_address) do
      {:ok, stored_inbox_id}
    else
      nil -> {:error, :xmtp_identity_required}
      false -> {:error, :xmtp_identity_required}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec complete_identity(HumanUser.t(), String.t(), map()) ::
          {:ok, HumanUser.t()} | {:error, term()}
  def complete_identity(%HumanUser{} = human, wallet_address, attrs)
      when is_binary(wallet_address) and is_map(attrs) do
    client = %Client{runtime: @runtime_name, id: Map.get(attrs, "client_id")}
    wallet_address = String.downcase(wallet_address)

    with {:ok, expected_wallet_address} <- required_string(attrs, "wallet_address"),
         :ok <- ensure_wallet_match(wallet_address, expected_wallet_address),
         {:ok, client_id} <- required_string(attrs, "client_id"),
         {:ok, signature_request_id} <- required_string(attrs, "signature_request_id"),
         {:ok, signature} <- required_string(attrs, "signature"),
         :ok <-
           Clients.unsafe_apply_signature_request(
             %Client{client | id: client_id},
             signature_request_id,
             %{signature: signature, address: wallet_address}
           ),
         :ok <- ensure_client_registered(%Client{client | id: client_id}),
         {:ok, updated_human} <-
           Accounts.update_human(human, %{
             "wallet_address" => wallet_address,
             "xmtp_inbox_id" => derived_inbox_id(wallet_address)
           }) do
      {:ok, updated_human}
    end
  end

  defp create_signature_request(human, wallet_address) do
    identifier = wallet_identifier(wallet_address)

    with {:ok, client} <- Clients.build(@runtime_name, identifier),
         {:ok, challenge} <- Clients.unsafe_create_inbox_signature_text(client) do
      {:ok,
       {:signature_required, human,
        %{
          inbox_id: nil,
          wallet_address: wallet_address,
          client_id: client.id,
          signature_request_id: challenge.signature_request_id,
          signature_text: challenge.signature_text
        }}}
    end
  end

  defp wallet_identifier(wallet_address) do
    %Types.Identifier{
      identifier: String.downcase(wallet_address),
      identifier_kind: :ethereum
    }
  end

  defp derived_inbox_id(wallet_address) do
    {:ok, inbox_id} = XmtpElixirSdk.generate_inbox_id(wallet_identifier(wallet_address), 0, 1)
    inbox_id
  end

  defp wallet_address(%HumanUser{wallet_address: wallet_address}) do
    case normalize_string(wallet_address) do
      nil -> {:error, :wallet_address_required}
      value -> {:ok, String.downcase(value)}
    end
  end

  defp required_string(attrs, key) do
    case normalize_string(Map.get(attrs, key)) do
      nil -> {:error, {:missing, key}}
      value -> {:ok, value}
    end
  end

  defp ensure_wallet_match(wallet_address, expected_wallet_address) do
    if String.downcase(wallet_address) == String.downcase(expected_wallet_address) do
      :ok
    else
      {:error, :wallet_address_mismatch}
    end
  end

  defp ensure_client_registered(client) do
    case Clients.is_registered(client) do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, Error.internal("XMTP identity did not register", %{})}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(_value), do: nil

  defp normalized_inbox_id(value), do: normalize_string(value)
end
