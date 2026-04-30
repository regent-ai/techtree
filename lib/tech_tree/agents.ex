defmodule TechTree.Agents do
  @moduledoc false

  alias TechTree.Repo
  alias TechTree.Agents.AgentIdentity

  @spec upsert_verified_agent!(map()) :: AgentIdentity.t()
  def upsert_verified_agent!(attrs) do
    chain_id = normalize_integer(attrs, "chain_id")
    registry_address = normalize_address(attrs, "registry_address")
    token_id = normalize_decimal(attrs, "token_id")

    existing =
      Repo.get_by(AgentIdentity,
        chain_id: chain_id,
        registry_address: registry_address,
        token_id: token_id
      ) || %AgentIdentity{}

    status = resolved_status(existing, attrs)

    existing
    |> AgentIdentity.upsert_changeset(%{
      chain_id: chain_id,
      registry_address: registry_address,
      token_id: token_id,
      wallet_address: normalize_address(attrs, "wallet_address"),
      label: Map.get(attrs, "label"),
      status: status,
      last_verified_at: DateTime.utc_now()
    })
    |> Repo.insert_or_update!()
  end

  @spec get_agent!(integer()) :: AgentIdentity.t()
  def get_agent!(id), do: Repo.get!(AgentIdentity, id)

  @spec normalize_integer(map(), String.t()) :: integer()
  defp normalize_integer(attrs, key) do
    attrs
    |> fetch_value(key)
    |> case do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
      _ -> raise ArgumentError, "missing #{key}"
    end
  end

  @spec normalize_decimal(map(), String.t()) :: Decimal.t()
  defp normalize_decimal(attrs, key) do
    attrs
    |> fetch_value(key)
    |> case do
      %Decimal{} = value -> value
      value when is_integer(value) -> Decimal.new(value)
      value when is_binary(value) -> Decimal.new(value)
      _ -> raise ArgumentError, "missing #{key}"
    end
  end

  @spec normalize_string(map(), String.t()) :: String.t()
  defp normalize_string(attrs, key) do
    attrs
    |> fetch_value(key)
    |> case do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "missing #{key}"
    end
  end

  @spec normalize_address(map(), String.t()) :: String.t()
  defp normalize_address(attrs, key) do
    attrs
    |> normalize_string(key)
    |> String.downcase()
  end

  @spec fetch_value(map(), String.t()) :: term()
  defp fetch_value(attrs, "chain_id"), do: Map.get(attrs, "chain_id")

  defp fetch_value(attrs, "registry_address"),
    do: Map.get(attrs, "registry_address")

  defp fetch_value(attrs, "token_id"), do: Map.get(attrs, "token_id")

  defp fetch_value(attrs, "wallet_address"),
    do: Map.get(attrs, "wallet_address")

  defp fetch_value(attrs, "label"), do: Map.get(attrs, "label")
  defp fetch_value(attrs, "status"), do: Map.get(attrs, "status")

  @spec resolved_status(AgentIdentity.t(), map()) :: String.t()
  defp resolved_status(%AgentIdentity{id: nil}, attrs) do
    Map.get(attrs, "status") || "active"
  end

  defp resolved_status(%AgentIdentity{} = existing, _attrs) do
    existing.status || "active"
  end
end
