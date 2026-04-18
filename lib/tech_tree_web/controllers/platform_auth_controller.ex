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
         :ok <- ensure_human_allowed(human),
         {:ok, xmtp_result} <- XmtpIdentity.ensure_identity(human) do
      conn
      |> write_session(privy_user_id)
      |> json(session_response(human, xmtp_result))
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

      {:error, {:missing, key}} ->
        invalid_request(conn, missing_field_code(key), missing_field_message(key))

      {:error, :wallet_address_mismatch} ->
        invalid_request(
          conn,
          "wallet_address_mismatch",
          "Finish this step with the same wallet you connected."
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          ok: false,
          error: %{code: "session_invalid", details: ApiError.translate_changeset(changeset)}
        })

      {:error, :invalid_authorization_header} ->
        privy_required(conn)

      {:error, :invalid_token} ->
        privy_required(conn)

      {:error, :token_expired} ->
        privy_required(conn)

      {:error, :token_not_yet_valid} ->
        privy_required(conn)

      {:error, :privy_config_missing} ->
        privy_required(conn)

      {:error, {:invalid_verification_result, _result}} ->
        privy_required(conn)

      {:error, reason} ->
        unexpected_error(conn, reason)
    end
  end

  def complete_xmtp(conn, params) do
    with %{} = human <- current_human(conn),
         :ok <- ensure_human_allowed(human),
         {:ok, updated_human} <- XmtpIdentity.complete_identity(human, params) do
      json(conn, session_response(updated_human, {:ready, updated_human}))
    else
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          ok: false,
          error: %{
            code: "privy_session_required",
            message: "Connect your wallet before you finish room setup."
          }
        })

      {:error, :human_banned} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          ok: false,
          error: %{code: "human_banned", message: "Banned humans cannot finish room setup"}
        })

      {:error, {:missing, key}} ->
        invalid_request(conn, missing_field_code(key), missing_field_message(key))

      {:error, :wallet_address_required} ->
        invalid_request(conn, "wallet_address_required", "Connect a wallet before you continue.")

      {:error, :wallet_address_mismatch} ->
        invalid_request(
          conn,
          "wallet_address_mismatch",
          "Finish this step with the same wallet you connected."
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          ok: false,
          error: %{code: "session_invalid", details: ApiError.translate_changeset(changeset)}
        })

      {:error, reason} ->
        unexpected_error(conn, reason)
    end
  end

  def delete(conn, _params) do
    preserved_session =
      conn
      |> get_session()
      |> Map.drop([:privy_user_id, "privy_user_id"])

    conn
    |> delete_session(:privy_user_id)
    |> restore_session(preserved_session)
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
    |> put_session(:privy_user_id, privy_user_id)
  end

  defp restore_session(conn, session_values) do
    Enum.reduce(session_values, conn, fn {key, value}, acc ->
      put_session(acc, key, value)
    end)
  end

  defp session_response(human, xmtp_result \\ nil) do
    {resolved_human, xmtp_state} = resolve_session_state(human, xmtp_result)

    %{
      ok: true,
      human: %{
        id: resolved_human.id,
        privy_user_id: resolved_human.privy_user_id,
        wallet_address: resolved_human.wallet_address,
        display_name: resolved_human.display_name,
        role: resolved_human.role,
        xmtp_inbox_id: response_inbox_id(resolved_human, xmtp_state)
      },
      xmtp: xmtp_state
    }
  end

  defp invalid_request(conn, code, message) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: %{code: code, message: message}})
  end

  defp privy_required(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{
      ok: false,
      error: %{code: "privy_required", message: "Valid Privy JWT required"}
    })
  end

  defp resolve_session_state(human, nil), do: {human, xmtp_state(human)}

  defp resolve_session_state(_human, {:ready, updated_human}),
    do: {updated_human, ready_xmtp_state(updated_human)}

  defp resolve_session_state(_human, {:signature_required, updated_human, attrs}) do
    {updated_human, signature_required_xmtp_state(updated_human, attrs)}
  end

  defp resolve_session_state(human, _result), do: {human, xmtp_state(human)}

  defp xmtp_state(human) do
    case XmtpIdentity.ready_inbox_id(human) do
      {:ok, _inbox_id} ->
        ready_xmtp_state(human)

      {:error, _reason} ->
        nil
    end
  end

  defp ready_xmtp_state(human) do
    {:ok, inbox_id} = XmtpIdentity.ready_inbox_id(human)

    %{
      status: "ready",
      inbox_id: inbox_id,
      wallet_address: human.wallet_address
    }
  end

  defp signature_required_xmtp_state(human, attrs) do
    %{
      status: "signature_required",
      inbox_id: nil,
      wallet_address: human.wallet_address,
      client_id: Map.get(attrs, :client_id) || Map.get(attrs, "client_id"),
      signature_request_id:
        Map.get(attrs, :signature_request_id) || Map.get(attrs, "signature_request_id"),
      signature_text: Map.get(attrs, :signature_text) || Map.get(attrs, "signature_text")
    }
  end

  defp response_inbox_id(_human, xmtp_state) do
    case xmtp_state do
      %{"status" => "ready", "inbox_id" => inbox_id} -> inbox_id
      %{status: "ready", inbox_id: inbox_id} -> inbox_id
      _ -> nil
    end
  end

  defp missing_field_code(key), do: "missing_" <> to_string(key)

  defp missing_field_message(key) do
    case key do
      "wallet_address" -> "Connect a wallet before you continue."
      "client_id" -> "Try connecting again before you finish room setup."
      "signature_request_id" -> "Try connecting again before you finish room setup."
      "signature" -> "Sign the wallet message before you continue."
      _ -> "Finish every required step before you continue."
    end
  end

  defp unexpected_error(conn, _reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      ok: false,
      error: %{
        code: "xmtp_setup_failed",
        message: "We could not finish secure room setup. Try again."
      }
    })
  end
end
