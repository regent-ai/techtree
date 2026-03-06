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

    HumanUser.changeset(human, Map.put(attrs, "privy_user_id", privy_user_id))
    |> Repo.insert_or_update()
  end

  @spec update_human(HumanUser.t(), map()) :: {:ok, HumanUser.t()} | {:error, Ecto.Changeset.t()}
  def update_human(%HumanUser{} = human, attrs) when is_map(attrs) do
    human
    |> HumanUser.changeset(attrs)
    |> Repo.update()
  end
end
