defmodule TechTreeWeb.RequirePrivyJWTTest do
  use TechTreeWeb.ConnCase, async: false

  import TechTree.PhaseDApiSupport

  alias TechTree.Accounts

  setup do
    privy = setup_privy_config!()

    on_exit(fn ->
      privy.restore.()
    end)

    {:ok, privy: privy}
  end

  test "rejects expired Privy JWTs", %{privy: privy} do
    token = privy_token("privy-expired-user", privy.app_id, privy.private_pem, -60)

    assert %{"error" => %{"code" => "privy_required"}} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> put_req_header("authorization", "Bearer #{token}")
             |> get("/v1/trollbox/membership")
             |> json_response(401)
  end

  test "accepts valid Privy JWTs", %{privy: privy} do
    token = privy_token("privy-valid-user", privy.app_id, privy.private_pem, 3600)

    assert %{"data" => %{"state" => "room_unavailable"}} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> put_req_header("authorization", "Bearer #{token}")
             |> get("/v1/trollbox/membership")
             |> json_response(200)
  end

  test "rejects banned humans even with a valid Privy JWT", %{privy: privy} do
    {:ok, _human} =
      Accounts.upsert_human_by_privy_id("privy-banned-user", %{
        "display_name" => "Banned User",
        "role" => "banned"
      })

    token = privy_token("privy-banned-user", privy.app_id, privy.private_pem, 3600)

    assert %{"error" => %{"code" => "human_banned"}} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> put_req_header("authorization", "Bearer #{token}")
             |> post("/v1/trollbox/messages", %{"body" => "hello from banned privy"})
             |> json_response(403)
  end

  defp privy_token(privy_user_id, app_id, private_pem, exp_offset_seconds) do
    now = System.system_time(:second)

    claims = %{
      "iss" => "privy.io",
      "sub" => privy_user_id,
      "aud" => app_id,
      "iat" => now,
      "exp" => now + exp_offset_seconds
    }

    private_jwk = JOSE.JWK.from_pem(private_pem)

    {_, token} =
      private_jwk
      |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims)
      |> JOSE.JWS.compact()

    token
  end
end
