defmodule TechTree.BBH.Helpers do
  @moduledoc false

  alias TechTree.BBH.Capsule
  alias TechTree.Repo

  def fetch_capsule(capsule_id) when is_binary(capsule_id) do
    case Repo.get(Capsule, capsule_id) do
      nil -> {:error, :capsule_not_found}
      capsule -> {:ok, capsule}
    end
  end

  def required_wallet(agent_claims) do
    case Map.get(agent_claims || %{}, "wallet_address") do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "wallet_address is required"
    end
  end

  def required_binary(attrs, key) do
    case fetch_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "#{key} is required"
    end
  end

  def optional_binary(attrs, key) do
    case fetch_value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  def required_map(attrs, key) do
    case fetch_value(attrs, key) do
      value when is_map(value) -> value
      _ -> raise ArgumentError, "#{key} is required"
    end
  end

  def optional_map(attrs, key) do
    case fetch_value(attrs, key) do
      value when is_map(value) -> value
      _ -> nil
    end
  end

  def fetch_value(attrs, key) when is_map(attrs) and is_binary(key) do
    try do
      case Map.fetch(attrs, key) do
        {:ok, value} ->
          value

        :error ->
          atom_key = String.to_existing_atom(key)
          Map.get(attrs, atom_key)
      end
    rescue
      ArgumentError -> nil
    end
  end

  def unique_suffix do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string(36)
  end

  def draft_capsule_id do
    "capsule_draft_" <> unique_suffix()
  end

  def random_hex(length) do
    bytes = div(length + 1, 2)

    Base.encode16(:crypto.strong_rand_bytes(bytes), case: :lower)
    |> binary_part(0, length)
  end

  def generated_orcid_id(wallet_address) when is_binary(wallet_address) do
    digits =
      wallet_address
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> String.replace(~r/[^0-9]/, "")
      |> Kernel.<>("0000000000000000")
      |> binary_part(0, 16)

    [
      binary_part(digits, 0, 4),
      binary_part(digits, 4, 4),
      binary_part(digits, 8, 4),
      binary_part(digits, 12, 4)
    ]
    |> Enum.join("-")
  end

  def infer_mode(attrs) do
    if Map.get(attrs, "family_ref") || Map.get(attrs, :family_ref), do: "family", else: "fixed"
  end
end
