defmodule TechTree.PrivyTest do
  use ExUnit.Case, async: false

  import TechTree.PhaseDApiSupport, only: [setup_privy_config!: 0]

  alias TechTree.Privy

  setup do
    privy = setup_privy_config!()

    on_exit(fn ->
      privy.restore.()
    end)

    {:ok, privy: privy}
  end

  test "verifies a valid Privy JWT", %{privy: privy} do
    token = privy_token("privy-valid-user", privy.app_id, privy.private_pem, 0, 3600)

    assert {:ok, %{privy_user_id: "privy-valid-user"}} = Privy.verify_token(token)
  end

  test "rejects Privy JWTs issued in the future", %{privy: privy} do
    token = privy_token("privy-future-user", privy.app_id, privy.private_pem, 300, 3600)

    assert {:error, :token_not_yet_valid} = Privy.verify_token(token)
  end

  test "rejects Privy JWTs that are not yet valid via nbf", %{privy: privy} do
    token =
      privy_token(
        "privy-nbf-user",
        privy.app_id,
        privy.private_pem,
        0,
        3600,
        300
      )

    assert {:error, :token_not_yet_valid} = Privy.verify_token(token)
  end

  defp privy_token(
         privy_user_id,
         app_id,
         private_pem,
         iat_offset_seconds,
         exp_offset_seconds,
         nbf_offset_seconds \\ nil
       ) do
    now = System.system_time(:second)

    claims = %{
      "iss" => "privy.io",
      "sub" => privy_user_id,
      "aud" => app_id,
      "iat" => now + iat_offset_seconds,
      "exp" => now + exp_offset_seconds
    }

    claims =
      case nbf_offset_seconds do
        nil -> claims
        offset -> Map.put(claims, "nbf", now + offset)
      end

    private_jwk = JOSE.JWK.from_pem(private_pem)

    {_, token} =
      private_jwk
      |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims)
      |> JOSE.JWS.compact()

    token
  end
end
