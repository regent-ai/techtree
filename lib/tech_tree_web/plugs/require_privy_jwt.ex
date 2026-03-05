defmodule TechTreeWeb.Plugs.RequirePrivyJWT do
  @moduledoc false

  import Plug.Conn

  alias TechTree.Accounts
  alias TechTreeWeb.ApiError

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    with {:ok, token} <- fetch_bearer_token(conn),
         {:ok, claims} <- verify_privy_token(token),
         {:ok, privy_user_id} <- fetch_subject(claims),
         {:ok, human} <- Accounts.upsert_human_by_privy_id(privy_user_id, %{}) do
      assign(conn, :current_human, human)
    else
      _ -> unauthorized(conn)
    end
  end

  @spec verify_privy_token(String.t()) :: {:ok, map()} | {:error, term()}
  defp verify_privy_token(token) do
    with {:ok, app_id, verification_key} <- fetch_privy_config(),
         signer <- Joken.Signer.create("ES256", %{"pem" => verification_key}),
         {:ok, claims} <- Joken.verify(token, signer),
         :ok <- validate_issuer(claims),
         :ok <- validate_audience(claims, app_id),
         :ok <- validate_time_claims(claims) do
      {:ok, claims}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_token}
    end
  rescue
    _ -> {:error, :invalid_token}
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

  @spec fetch_privy_config() :: {:ok, String.t(), String.t()} | {:error, :missing_privy_config}
  defp fetch_privy_config do
    privy_config = Application.get_env(:tech_tree, :privy, [])
    app_id = Keyword.get(privy_config, :app_id)
    verification_key = Keyword.get(privy_config, :verification_key)

    if is_binary(app_id) and app_id != "" and is_binary(verification_key) and
         verification_key != "" do
      {:ok, app_id, verification_key}
    else
      {:error, :missing_privy_config}
    end
  end

  @spec validate_issuer(map()) :: :ok | {:error, :invalid_claims}
  defp validate_issuer(%{"iss" => "privy.io"}), do: :ok
  defp validate_issuer(_claims), do: {:error, :invalid_claims}

  @spec validate_audience(map(), String.t()) :: :ok | {:error, :invalid_claims}
  defp validate_audience(%{"aud" => audience}, app_id) when is_binary(audience) do
    if audience == app_id, do: :ok, else: {:error, :invalid_claims}
  end

  defp validate_audience(%{"aud" => audiences}, app_id) when is_list(audiences) do
    if app_id in audiences, do: :ok, else: {:error, :invalid_claims}
  end

  defp validate_audience(_claims, _app_id), do: {:error, :invalid_claims}

  @spec validate_time_claims(map()) :: :ok | {:error, :invalid_claims}
  defp validate_time_claims(claims) do
    now = System.system_time(:second)

    with {:ok, exp} <- fetch_integer_claim(claims, "exp"),
         :ok <- ensure_future(exp, now),
         :ok <- validate_not_before(claims, now),
         :ok <- validate_issued_at(claims, now) do
      :ok
    end
  end

  @spec validate_not_before(map(), integer()) :: :ok | {:error, :invalid_claims}
  defp validate_not_before(claims, now) do
    case Map.fetch(claims, "nbf") do
      :error ->
        :ok

      {:ok, nbf} when is_integer(nbf) and nbf <= now ->
        :ok

      _ ->
        {:error, :invalid_claims}
    end
  end

  @spec validate_issued_at(map(), integer()) :: :ok | {:error, :invalid_claims}
  defp validate_issued_at(claims, now) do
    case Map.fetch(claims, "iat") do
      :error ->
        :ok

      {:ok, iat} when is_integer(iat) and iat <= now + 60 ->
        :ok

      _ ->
        {:error, :invalid_claims}
    end
  end

  @spec fetch_integer_claim(map(), String.t()) :: {:ok, integer()} | {:error, :invalid_claims}
  defp fetch_integer_claim(claims, claim_name) do
    case Map.fetch(claims, claim_name) do
      {:ok, value} when is_integer(value) -> {:ok, value}
      _ -> {:error, :invalid_claims}
    end
  end

  @spec ensure_future(integer(), integer()) :: :ok | {:error, :invalid_claims}
  defp ensure_future(exp, now) when exp > now, do: :ok
  defp ensure_future(_exp, _now), do: {:error, :invalid_claims}

  @spec fetch_subject(map()) :: {:ok, String.t()} | {:error, :invalid_claims}
  defp fetch_subject(%{"sub" => privy_user_id})
       when is_binary(privy_user_id) and privy_user_id != "" do
    {:ok, privy_user_id}
  end

  defp fetch_subject(_claims), do: {:error, :invalid_claims}

  @spec unauthorized(Plug.Conn.t()) :: Plug.Conn.t()
  defp unauthorized(conn) do
    ApiError.render_halted(conn, :unauthorized, %{
      code: "privy_required",
      message: "Valid Privy JWT required"
    })
  end
end
