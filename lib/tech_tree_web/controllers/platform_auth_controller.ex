defmodule TechTreeWeb.PlatformAuthController do
  @moduledoc false
  use TechTreeWeb, :controller

  alias TechTree.Accounts
  alias TechTree.Privy

  @wallet_address_regex ~r/^0x[0-9a-fA-F]{40}$/

  def create(conn, params) do
    with {:ok, token} <- fetch_bearer_token(conn),
         {:ok, %{privy_user_id: privy_user_id}} <- Privy.verify_token(token),
         attrs <- session_attrs(params),
         {:ok, human} <- Accounts.upsert_human_by_privy_id(privy_user_id, attrs),
         :ok <- ensure_human_allowed(human) do
      conn
      |> configure_session(renew: true)
      |> put_session(:privy_user_id, privy_user_id)
      |> json(%{
        ok: true,
        human: %{
          id: human.id,
          privy_user_id: human.privy_user_id,
          wallet_address: human.wallet_address,
          display_name: human.display_name,
          role: human.role
        }
      })
    else
      {:error, :human_banned} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          ok: false,
          error: %{code: "human_banned", message: "Banned humans cannot open platform sessions"}
        })

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          ok: false,
          error: %{code: "privy_required", message: "Valid Privy JWT required"}
        })
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> json(%{ok: true})
  end

  defp fetch_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        normalized = String.trim(token)
        if normalized == "", do: {:error, :invalid_authorization_header}, else: {:ok, normalized}

      _ ->
        {:error, :invalid_authorization_header}
    end
  end

  defp session_attrs(params) do
    %{}
    |> maybe_put("wallet_address", normalize_wallet_address(Map.get(params, "wallet_address")))
    |> maybe_put("display_name", normalize_display_name(Map.get(params, "display_name")))
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, _key, ""), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp normalize_wallet_address(value) when is_binary(value) do
    trimmed = String.trim(value)

    if Regex.match?(@wallet_address_regex, trimmed) do
      trimmed
    else
      nil
    end
  end

  defp normalize_wallet_address(_value), do: nil

  defp normalize_display_name(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_display_name(_value), do: nil

  defp ensure_human_allowed(%{role: "banned"}), do: {:error, :human_banned}
  defp ensure_human_allowed(_human), do: :ok
end
