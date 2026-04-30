defmodule TechTreeWeb.Plugs.RequirePrivyJWT do
  @moduledoc false

  import Plug.Conn

  alias TechTree.Accounts
  alias TechTree.Privy
  alias TechTreeWeb.ApiError

  @pending_wallet_session_key :privy_pending_wallet_address

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    conn = fetch_session(conn)

    with {:ok, token} <- fetch_bearer_token(conn),
         {:ok, %{privy_user_id: privy_user_id}} <- Privy.verify_token(token),
         :ok <- ensure_existing_human_allowed(Accounts.get_human_by_privy_id(privy_user_id)),
         {:ok, human} <- Accounts.upsert_human_by_privy_id(privy_user_id, %{}),
         :ok <- ensure_human_allowed(human) do
      human
      |> overlay_pending_wallet(conn, privy_user_id)
      |> then(&assign(conn, :current_human, &1))
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
      "code" => "privy_required",
      "message" => "Valid Privy JWT required"
    })
  end

  @spec forbidden(Plug.Conn.t()) :: Plug.Conn.t()
  defp forbidden(conn) do
    ApiError.render_halted(conn, :forbidden, %{
      "code" => "human_banned",
      "message" => "Banned humans cannot perform authenticated actions"
    })
  end

  defp ensure_human_allowed(%{role: "banned"}), do: {:error, :human_banned}
  defp ensure_human_allowed(_human), do: :ok

  defp ensure_existing_human_allowed(%{role: "banned"}), do: {:error, :human_banned}
  defp ensure_existing_human_allowed(_human), do: :ok

  defp overlay_pending_wallet(human, conn, privy_user_id) do
    if get_session(conn, :privy_user_id) == privy_user_id do
      case normalize_wallet_address(get_session(conn, @pending_wallet_session_key)) do
        nil -> human
        wallet_address -> %{human | wallet_address: wallet_address}
      end
    else
      human
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
