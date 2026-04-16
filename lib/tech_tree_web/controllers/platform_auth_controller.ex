defmodule TechTreeWeb.PlatformAuthController do
  @moduledoc false
  use TechTreeWeb, :controller

  alias TechTree.Accounts
  alias TechTree.Privy
  alias TechTree.XmtpIdentity
  alias TechTreeWeb.ApiError

  @wallet_address_regex ~r/^0x[0-9a-fA-F]{40}$/

  def csrf(conn, _params) do
    token = Plug.CSRFProtection.get_csrf_token()

    conn
    |> put_session("_csrf_token", Plug.CSRFProtection.dump_state())
    |> json(%{ok: true, csrf_token: token})
  end

  def show(conn, _params) do
    case current_human(conn) do
      nil ->
        json(conn, %{ok: true, human: nil, xmtp: nil})

      human ->
        json(conn, session_response(human))
    end
  end

  def create(conn, params) do
    with {:ok, privy_user_id} <- verify_privy_user_id(conn),
         {:ok, attrs} <- session_attrs(params),
         :ok <- ensure_existing_human_allowed(Accounts.get_human_by_privy_id(privy_user_id)),
         {:ok, human} <- Accounts.open_privy_session(privy_user_id, attrs),
         {:ok, human} <- clear_stale_inbox_id(human),
         :ok <- ensure_human_allowed(human) do
      conn
      |> write_session(privy_user_id)
      |> json(session_response(human))
    else
      {:error, :human_banned} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          ok: false,
          error: %{code: "human_banned", message: "Banned humans cannot open platform sessions"}
        })

      {:error, :wallet_address_required} ->
        invalid_request(conn, "wallet_address_required", "Connect a wallet before you continue.")

      {:error, :wallet_address_invalid} ->
        invalid_request(conn, "wallet_address_invalid", "Enter a valid wallet address.")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          ok: false,
          error: %{code: "session_invalid", details: ApiError.translate_changeset(changeset)}
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

  defp current_human(conn) do
    conn
    |> get_session(:privy_user_id)
    |> Accounts.get_human_by_privy_id()
  end

  defp verify_privy_user_id(conn) do
    with {:ok, token} <- fetch_bearer_token(conn),
         {:ok, %{privy_user_id: privy_user_id}} <- Privy.verify_token(token) do
      {:ok, privy_user_id}
    end
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
    with {:ok, wallet_address} <- required_wallet_address(params) do
      {:ok,
       %{}
       |> Map.put("wallet_address", wallet_address)
       |> maybe_put("display_name", normalize_display_name(Map.get(params, "display_name")))}
    end
  end

  defp required_wallet_address(params) do
    case normalize_wallet_address(Map.get(params, "wallet_address")) do
      nil -> {:error, :wallet_address_invalid}
      wallet_address -> {:ok, wallet_address}
    end
  end

  defp maybe_put(attrs, _key, nil), do: attrs
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

  defp normalize_display_name(value) when is_binary(value), do: normalize_string(value)
  defp normalize_display_name(_value), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(_value), do: nil

  defp ensure_human_allowed(%{role: "banned"}), do: {:error, :human_banned}
  defp ensure_human_allowed(_human), do: :ok

  defp ensure_existing_human_allowed(%{role: "banned"}), do: {:error, :human_banned}
  defp ensure_existing_human_allowed(_human), do: :ok

  defp write_session(conn, privy_user_id) do
    conn
    |> configure_session(renew: true)
    |> put_session(:privy_user_id, privy_user_id)
  end

  defp session_response(human) do
    xmtp_state = xmtp_state(human)

    %{
      ok: true,
      human: %{
        id: human.id,
        privy_user_id: human.privy_user_id,
        wallet_address: human.wallet_address,
        display_name: human.display_name,
        role: human.role,
        xmtp_inbox_id: response_inbox_id(human)
      },
      xmtp: xmtp_state
    }
  end

  defp invalid_request(conn, code, message) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: %{code: code, message: message}})
  end

  defp clear_stale_inbox_id(%{xmtp_inbox_id: nil} = human), do: {:ok, human}

  defp clear_stale_inbox_id(human) do
    case XmtpIdentity.ready_inbox_id(human) do
      {:ok, _inbox_id} ->
        {:ok, human}

      {:error, _reason} ->
        Accounts.update_human(human, %{"xmtp_inbox_id" => nil})
    end
  end

  defp xmtp_state(human) do
    case XmtpIdentity.ready_inbox_id(human) do
      {:ok, inbox_id} ->
        %{
          status: "ready",
          inbox_id: inbox_id,
          wallet_address: human.wallet_address
        }

      {:error, _reason} ->
        nil
    end
  end

  defp response_inbox_id(human) do
    case XmtpIdentity.ready_inbox_id(human) do
      {:ok, inbox_id} -> inbox_id
      {:error, _reason} -> nil
    end
  end
end
