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
    attrs = normalize_wallet_attrs(attrs)

    attrs =
      case Map.get(attrs, "wallet_address") do
        wallet_address when is_binary(wallet_address) and wallet_address != "" ->
          current_wallet = normalize_wallet_address(human.wallet_address)

          if current_wallet != nil and current_wallet == wallet_address do
            attrs
          else
            Map.put(attrs, "xmtp_inbox_id", nil)
          end

        _ ->
          attrs
      end

    HumanUser.changeset(human, Map.put(attrs, "privy_user_id", privy_user_id))
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
