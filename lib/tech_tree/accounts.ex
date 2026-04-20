defmodule TechTree.Accounts do
  @moduledoc false

  alias TechTree.Repo
  alias TechTree.Accounts.HumanUser

  @spec get_human_by_privy_id(String.t() | nil) :: HumanUser.t() | nil
  def get_human_by_privy_id(nil), do: nil

  def get_human_by_privy_id(privy_user_id),
    do: Repo.get_by(HumanUser, privy_user_id: privy_user_id)

  @spec upsert_human_by_privy_id(String.t(), map()) ::
          {:ok, HumanUser.t()} | {:error, Ecto.Changeset.t()}
  def upsert_human_by_privy_id(privy_user_id, attrs) do
    human = Repo.get_by(HumanUser, privy_user_id: privy_user_id) || %HumanUser{}

    HumanUser.changeset(
      human,
      Map.put(normalize_wallet_attrs(attrs), "privy_user_id", privy_user_id)
    )
    |> Repo.insert_or_update()
  end

  @spec open_privy_session(String.t(), map()) ::
          {:ok, HumanUser.t()} | {:error, Ecto.Changeset.t()}
  def open_privy_session(privy_user_id, attrs) when is_binary(privy_user_id) and is_map(attrs) do
    human = Repo.get_by(HumanUser, privy_user_id: privy_user_id) || %HumanUser{}

    attrs
    |> Map.take(["display_name"])
    |> Map.put("privy_user_id", privy_user_id)
    |> then(&HumanUser.changeset(human, &1))
    |> Repo.insert_or_update()
  end

  @spec update_human(HumanUser.t(), map()) :: {:ok, HumanUser.t()} | {:error, Ecto.Changeset.t()}
  def update_human(%HumanUser{} = human, attrs) when is_map(attrs) do
    human
    |> HumanUser.changeset(attrs)
    |> Repo.update()
  end

  defp normalize_wallet_attrs(attrs) when is_map(attrs) do
    case normalize_wallet_address(Map.get(attrs, "wallet_address")) do
      nil -> attrs
      wallet_address -> Map.put(attrs, "wallet_address", wallet_address)
    end
  end

  defp normalize_wallet_address(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      wallet_address -> String.downcase(wallet_address)
    end
  end

  defp normalize_wallet_address(_value), do: nil
end
