defmodule TechTreeWeb.Plugs.LoadCurrentHuman do
  @moduledoc false

  import Plug.Conn

  alias TechTree.Accounts

  @pending_wallet_session_key :privy_pending_wallet_address

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    privy_user_id = get_session(conn, :privy_user_id)

    human =
      if privy_user_id do
        Accounts.get_human_by_privy_id(privy_user_id)
      end

    case human do
      %{role: "banned"} ->
        conn
        |> delete_session(:privy_user_id)
        |> delete_session("privy_user_id")
        |> delete_session(@pending_wallet_session_key)
        |> delete_session(Atom.to_string(@pending_wallet_session_key))
        |> assign(:current_human, nil)

      _ ->
        assign(conn, :current_human, human)
    end
  end
end
