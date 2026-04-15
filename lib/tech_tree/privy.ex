defmodule TechTree.Privy do
  @moduledoc false

  @privy_issuer "privy.io"

  @spec verify_token(String.t() | nil) :: {:ok, %{privy_user_id: String.t()}} | {:error, term()}
  def verify_token(token) when is_binary(token) do
    with {:ok, app_id, verification_key} <- privy_config(),
         {:ok, jwt} <- verify_signature(token, verification_key),
         {:ok, claims} <- validate_claims(jwt.fields, app_id) do
      {:ok, %{privy_user_id: claims["sub"]}}
    end
  end

  def verify_token(_token), do: {:error, :invalid_token}

  @spec privy_config() :: {:ok, String.t(), String.t()} | {:error, term()}
  defp privy_config do
    cfg = Application.get_env(:tech_tree, :privy, [])
    app_id = config_value(cfg, :app_id)
    verification_key = config_value(cfg, :verification_key)

    if is_binary(app_id) and String.trim(app_id) != "" and is_binary(verification_key) and
         String.trim(verification_key) != "" do
      {:ok, app_id, verification_key}
    else
      {:error, :privy_config_missing}
    end
  end

  @spec verify_signature(String.t(), String.t()) :: {:ok, JOSE.JWT.t()} | {:error, term()}
  defp verify_signature(token, verification_key) do
    jwk = JOSE.JWK.from_pem(verification_key)

    case JOSE.JWT.verify_strict(jwk, ["ES256"], token) do
      {true, jwt, _jws} -> {:ok, jwt}
      {false, _jwt, _jws} -> {:error, :invalid_token}
      other -> {:error, {:invalid_verification_result, other}}
    end
  rescue
    _ -> {:error, :invalid_token}
  end

  @spec validate_claims(map(), String.t()) ::
          {:ok, map()}
          | {:error, :invalid_token | :token_expired | :token_not_yet_valid}
  defp validate_claims(claims, app_id) when is_map(claims) do
    now = System.system_time(:second)

    with :ok <- ensure_claim(claims, "iss", @privy_issuer),
         :ok <- ensure_claim(claims, "aud", app_id),
         {:ok, sub} <- claim_as_string(claims, "sub"),
         {:ok, iat} <- claim_as_integer(claims, "iat"),
         :ok <- ensure_timestamp_not_after_now(iat, now),
         :ok <- ensure_optional_timestamp_not_after_now(claims, "nbf", now),
         {:ok, exp} <- claim_as_integer(claims, "exp"),
         :ok <- ensure_timestamp_after_now(exp, now) do
      {:ok, Map.put(claims, "sub", sub)}
    else
      {:error, _} = error -> error
      :error -> {:error, :invalid_token}
      _ -> {:error, :invalid_token}
    end
  end

  defp validate_claims(_claims, _app_id), do: {:error, :invalid_token}

  @spec ensure_claim(map(), String.t(), term()) :: :ok | {:error, :invalid_token}
  defp ensure_claim(claims, key, expected) do
    case Map.get(claims, key) do
      value when value == expected -> :ok
      _ -> {:error, :invalid_token}
    end
  end

  @spec ensure_timestamp_not_after_now(integer(), integer()) ::
          :ok | {:error, :token_not_yet_valid}
  defp ensure_timestamp_not_after_now(timestamp, now)
       when is_integer(timestamp) and timestamp <= now,
       do: :ok

  defp ensure_timestamp_not_after_now(_timestamp, _now), do: {:error, :token_not_yet_valid}

  @spec ensure_optional_timestamp_not_after_now(map(), String.t(), integer()) ::
          :ok | {:error, :invalid_token | :token_not_yet_valid}
  defp ensure_optional_timestamp_not_after_now(claims, key, now) do
    case claim_as_optional_integer(claims, key) do
      {:ok, nil} ->
        :ok

      {:ok, timestamp} ->
        ensure_timestamp_not_after_now(timestamp, now)

      {:error, _} = error ->
        error
    end
  end

  @spec ensure_timestamp_after_now(integer(), integer()) ::
          :ok | {:error, :token_expired}
  defp ensure_timestamp_after_now(timestamp, now) when is_integer(timestamp) and timestamp > now,
    do: :ok

  defp ensure_timestamp_after_now(_timestamp, _now), do: {:error, :token_expired}

  @spec claim_as_string(map(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp claim_as_string(claims, key) do
    case Map.get(claims, key) do
      value when is_binary(value) ->
        if String.trim(value) != "" do
          {:ok, value}
        else
          {:error, :invalid_token}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  @spec claim_as_optional_integer(map(), String.t()) :: {:ok, integer() | nil} | {:error, term()}
  defp claim_as_optional_integer(claims, key) do
    case Map.get(claims, key) do
      nil ->
        {:ok, nil}

      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {int, ""} -> {:ok, int}
          _ -> {:error, :invalid_token}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  @spec claim_as_integer(map(), String.t()) :: {:ok, integer()} | {:error, term()}
  defp claim_as_integer(claims, key) do
    case Map.get(claims, key) do
      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {int, ""} -> {:ok, int}
          _ -> {:error, :invalid_token}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  @spec config_value(keyword() | map(), atom()) :: term()
  defp config_value(cfg, key) when is_list(cfg), do: Keyword.get(cfg, key)
  defp config_value(cfg, key) when is_map(cfg), do: Map.get(cfg, key)
  defp config_value(_cfg, _key), do: nil
end
