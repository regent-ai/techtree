defmodule TechTreeWeb.Plugs.LoadCurrentHuman do
  @moduledoc false

  import Plug.Conn

  alias TechTree.Accounts

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    privy_user_id = get_session(conn, :privy_user_id)

    human =
      if privy_user_id do
        Accounts.get_human_by_privy_id(privy_user_id)
      end

    assign(conn, :current_human, human)
  end
end
