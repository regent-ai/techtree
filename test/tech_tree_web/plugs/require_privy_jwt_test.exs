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
             |> get("/v1/chatbox/membership")
             |> json_response(401)
  end

  test "accepts valid Privy JWTs", %{privy: privy} do
    token = privy_token("privy-valid-user", privy.app_id, privy.private_pem, 3600)

    assert %{"data" => %{"state" => "room_unavailable"}} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> put_req_header("authorization", "Bearer #{token}")
             |> get("/v1/chatbox/membership")
             |> json_response(200)
  end

  test "rejects banned humans even with a valid Privy JWT", %{privy: privy} do
    wallet_address = "0x1234567890123456789012345678901234567890"

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("privy-banned-user", %{
        "display_name" => "Banned User",
        "wallet_address" => wallet_address,
        "xmtp_inbox_id" => deterministic_inbox_id(wallet_address),
        "role" => "banned"
      })

    human_id = human.id

    token = privy_token("privy-banned-user", privy.app_id, privy.private_pem, 3600)

    assert %{"error" => %{"code" => "human_banned"}} =
             Phoenix.ConnTest.build_conn()
             |> put_req_header("accept", "application/json")
             |> put_req_header("authorization", "Bearer #{token}")
             |> post("/v1/chatbox/messages", %{"body" => "hello from banned privy"})
             |> json_response(403)

    assert %TechTree.Accounts.HumanUser{
             id: ^human_id,
             display_name: "Banned User",
             wallet_address: ^wallet_address,
             xmtp_inbox_id: xmtp_inbox_id,
             role: "banned"
           } = Accounts.get_human_by_privy_id("privy-banned-user")

    assert xmtp_inbox_id == deterministic_inbox_id(wallet_address)
  end

  test "uses the pending browser wallet when checking public-room readiness", %{privy: privy} do
    ready_wallet = "0x2234567890123456789012345678901234567890"
    pending_wallet = "0x3234567890123456789012345678901234567890"

    {:ok, _room} =
      TechTree.XMTPMirror.ensure_room(%{
        room_key: "public-chatbox",
        name: "Public Chat",
        description: "Pending wallet coverage"
      })

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("privy-pending-wallet-user", %{
        "display_name" => "Pending Wallet User",
        "wallet_address" => ready_wallet,
        "xmtp_inbox_id" => deterministic_inbox_id(ready_wallet)
      })

    token = privy_token("privy-pending-wallet-user", privy.app_id, privy.private_pem, 3600)

    assert %{"data" => %{"state" => "setup_required"}} =
             Phoenix.ConnTest.build_conn()
             |> init_test_session(%{
               privy_user_id: human.privy_user_id,
               privy_pending_wallet_address: pending_wallet
             })
             |> put_req_header("accept", "application/json")
             |> put_req_header("authorization", "Bearer #{token}")
             |> get("/v1/chatbox/membership")
             |> json_response(200)
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
