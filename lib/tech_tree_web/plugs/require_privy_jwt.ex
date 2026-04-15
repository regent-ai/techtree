defmodule TechTreeWeb.Plugs.RequirePrivyJWT do
  @moduledoc false

  import Plug.Conn

  alias TechTree.Accounts
  alias TechTree.Privy
  alias TechTreeWeb.ApiError

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    with {:ok, token} <- fetch_bearer_token(conn),
         {:ok, %{privy_user_id: privy_user_id}} <- Privy.verify_token(token),
         :ok <- ensure_existing_human_allowed(Accounts.get_human_by_privy_id(privy_user_id)),
         {:ok, human} <- Accounts.upsert_human_by_privy_id(privy_user_id, %{}),
         :ok <- ensure_human_allowed(human) do
      assign(conn, :current_human, human)
    else
      {:error, :human_banned} -> forbidden(conn)
      _ -> unauthorized(conn)
    end
  end

  @spec fetch_bearer_token(Plug.Conn.t()) ::
          {:ok, String.t()} | {:error, :invalid_authorization_header}
  defp fetch_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        normalized = String.trim(token)
        if normalized == "", do: {:error, :invalid_authorization_header}, else: {:ok, normalized}

      _ ->
        {:error, :invalid_authorization_header}
    end
  end

  @spec unauthorized(Plug.Conn.t()) :: Plug.Conn.t()
  defp unauthorized(conn) do
    ApiError.render_halted(conn, :unauthorized, %{
      code: "privy_required",
      message: "Valid Privy JWT required"
    })
  end

  @spec forbidden(Plug.Conn.t()) :: Plug.Conn.t()
  defp forbidden(conn) do
    ApiError.render_halted(conn, :forbidden, %{
      code: "human_banned",
      message: "Banned humans cannot perform authenticated actions"
    })
  end

  defp ensure_human_allowed(%{role: "banned"}), do: {:error, :human_banned}
  defp ensure_human_allowed(_human), do: :ok

  defp ensure_existing_human_allowed(%{role: "banned"}), do: {:error, :human_banned}
  defp ensure_existing_human_allowed(_human), do: :ok
end
