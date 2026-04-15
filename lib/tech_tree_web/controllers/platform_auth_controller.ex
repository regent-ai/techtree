defmodule TechTreeWeb.PlatformAuthController do
  @moduledoc false
  use TechTreeWeb, :controller

  alias TechTree.Accounts
  alias TechTree.Privy
  alias TechTree.XmtpIdentity
  alias TechTreeWeb.ApiError
  alias XmtpElixirSdk.Error

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
        xmtp_state =
          case XmtpIdentity.ready_inbox_id(human) do
            {:ok, _inbox_id} -> ready_xmtp_state(human)
            {:error, _reason} -> %{status: "signature_required"}
          end

        json(conn, session_response(human, xmtp_state))
    end
  end

  def create(conn, params) do
    with {:ok, privy_user_id} <- verify_privy_user_id(conn),
         {:ok, attrs} <- session_attrs(params),
         :ok <- ensure_existing_human_allowed(Accounts.get_human_by_privy_id(privy_user_id)),
         {:ok, human} <- Accounts.open_privy_session(privy_user_id, attrs),
         :ok <- ensure_human_allowed(human) do
      case XmtpIdentity.ensure_identity(human) do
        {:ok, {:ready, ready_human}} ->
          conn
          |> write_session(privy_user_id)
          |> json(session_response(ready_human, ready_xmtp_state(ready_human)))

        {:ok, {:signature_required, pending_human, challenge}} ->
          conn
          |> write_session(privy_user_id)
          |> json(session_response(pending_human, signature_required_state(challenge)))

        {:error, reason} ->
          render_xmtp_error(conn, reason)
      end
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

  def complete_xmtp(conn, params) do
    with {:ok, privy_user_id} <- verify_privy_user_id(conn),
         {:ok, attrs} <- complete_xmtp_attrs(params),
         {:ok, human} <- fetch_existing_human(privy_user_id),
         :ok <- ensure_human_allowed(human),
         {:ok, completed_human} <- XmtpIdentity.complete_identity(human, attrs) do
      conn
      |> write_session(privy_user_id)
      |> json(session_response(completed_human, ready_xmtp_state(completed_human)))
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

      {:error, :xmtp_setup_required} ->
        invalid_request(conn, "xmtp_setup_required", "Start wallet setup from this page first.")

      {:error, :wallet_address_mismatch} ->
        invalid_request(
          conn,
          "wallet_address_mismatch",
          "Finish the wallet check with the same wallet you connected."
        )

      {:error, {:missing, key}} ->
        invalid_request(conn, "missing_#{key}", "Finish the wallet check from this page.")

      {:error, %Error{} = error} ->
        render_xmtp_error(conn, error)

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
    |> configure_session(renew: true)
    |> delete_session(:privy_user_id)
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

  defp complete_xmtp_attrs(params) do
    with {:ok, wallet_address} <- required_wallet_address(params),
         {:ok, client_id} <- required_string(params, "client_id"),
         {:ok, signature_request_id} <- required_string(params, "signature_request_id"),
         {:ok, signature} <- required_string(params, "signature") do
      {:ok,
       %{
         "wallet_address" => wallet_address,
         "client_id" => client_id,
         "signature_request_id" => signature_request_id,
         "signature" => signature
       }}
    end
  end

  defp required_wallet_address(params) do
    case normalize_wallet_address(Map.get(params, "wallet_address")) do
      nil -> {:error, :wallet_address_invalid}
      wallet_address -> {:ok, wallet_address}
    end
  end

  defp required_string(params, key) do
    case normalize_string(Map.get(params, key)) do
      nil -> {:error, {:missing, key}}
      value -> {:ok, value}
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

  defp fetch_existing_human(privy_user_id) do
    case Accounts.get_human_by_privy_id(privy_user_id) do
      nil -> {:error, :xmtp_setup_required}
      human -> {:ok, human}
    end
  end

  defp write_session(conn, privy_user_id) do
    conn
    |> configure_session(renew: true)
    |> put_session(:privy_user_id, privy_user_id)
  end

  defp session_response(human, xmtp_state) do
    %{
      ok: true,
      human: %{
        id: human.id,
        privy_user_id: human.privy_user_id,
        wallet_address: human.wallet_address,
        display_name: human.display_name,
        role: human.role,
        xmtp_inbox_id: response_inbox_id(human, xmtp_state)
      },
      xmtp: xmtp_state
    }
  end

  defp ready_xmtp_state(human) do
    {:ok, inbox_id} = XmtpIdentity.ready_inbox_id(human)

    %{
      status: "ready",
      inbox_id: inbox_id,
      wallet_address: human.wallet_address,
      client_id: nil,
      signature_request_id: nil,
      signature_text: nil
    }
  end

  defp signature_required_state(challenge) do
    %{
      status: "signature_required",
      inbox_id: Map.get(challenge, :inbox_id),
      wallet_address: Map.get(challenge, :wallet_address),
      client_id: Map.get(challenge, :client_id),
      signature_request_id: Map.get(challenge, :signature_request_id),
      signature_text: Map.get(challenge, :signature_text)
    }
  end

  defp invalid_request(conn, code, message) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: %{code: code, message: message}})
  end

  defp render_xmtp_error(conn, %Error{kind: :conflict, message: message}) do
    conn
    |> put_status(:conflict)
    |> json(%{ok: false, error: %{code: "xmtp_conflict", message: message}})
  end

  defp render_xmtp_error(conn, %Error{kind: :not_found, message: message}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: %{code: "xmtp_request_not_found", message: message}})
  end

  defp render_xmtp_error(conn, %Error{message: message}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{ok: false, error: %{code: "xmtp_identity_failed", message: message}})
  end

  defp render_xmtp_error(conn, :wallet_address_required) do
    invalid_request(conn, "wallet_address_required", "Connect a wallet before you continue.")
  end

  defp render_xmtp_error(conn, _reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      ok: false,
      error: %{code: "xmtp_identity_failed", message: "We could not finish secure room setup."}
    })
  end

  defp response_inbox_id(_human, %{status: "signature_required"}), do: nil

  defp response_inbox_id(human, %{status: "ready"}) do
    case XmtpIdentity.ready_inbox_id(human) do
      {:ok, inbox_id} -> inbox_id
      {:error, _reason} -> nil
    end
  end

  defp response_inbox_id(_human, _xmtp_state), do: nil
end
